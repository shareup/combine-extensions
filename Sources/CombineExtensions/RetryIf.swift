import Foundation
import Combine
import Synchronized

extension Publisher {
    public func retryIf<Context: Scheduler>(
        _ predicate: @escaping (Failure) -> Bool,
        after interval: Context.SchedulerTimeType.Stride,
        tolerance: Context.SchedulerTimeType.Stride? = nil,
        scheduler: Context,
        options: Context.SchedulerOptions? = nil
    ) -> Publishers.RetryIf<Self, Context> {
        retryIf(
            predicate,
            after: { _ in interval },
            tolerance: tolerance,
            scheduler: scheduler,
            options: options
        )
    }

    public func retryIf<Context: Scheduler>(
        _ predicate: @escaping (Failure) -> Bool,
        after interval: @escaping (Int) -> Context.SchedulerTimeType.Stride,
        tolerance: Context.SchedulerTimeType.Stride? = nil,
        scheduler: Context,
        options: Context.SchedulerOptions? = nil
    ) -> Publishers.RetryIf<Self, Context> {
        Publishers.RetryIf(
            upstream: self,
            retryIf: predicate,
            after: interval,
            tolerance: tolerance ?? scheduler.minimumTolerance,
            scheduler: scheduler,
            options: options
        )
    }
}

public extension Publishers {
    struct RetryIf<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream
        private let predicate: (Failure) -> Bool
        private let interval: (Int) -> Context.SchedulerTimeType.Stride
        private let tolerance: Context.SchedulerTimeType.Stride
        private let scheduler: Context
        private let options: Context.SchedulerOptions?

        public init(
            upstream: Upstream,
            retryIf predicate: @escaping (Failure) -> Bool,
            after interval: @escaping (Int) -> Context.SchedulerTimeType.Stride,
            tolerance: Context.SchedulerTimeType.Stride,
            scheduler: Context,
            options: Context.SchedulerOptions? = nil
        ) {
            self.upstream = upstream
            self.predicate = predicate
            self.interval = interval
            self.tolerance = tolerance
            self.scheduler = scheduler
            self.options = options
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Output == S.Input, Failure == S.Failure {
            let subscription = RetryIfSubscription(
                upstream: upstream,
                retryIf: predicate,
                interval: interval,
                tolerance: tolerance,
                scheduler: scheduler,
                options: options,
                subscriber: subscriber
            )
            upstream.receive(subscriber: subscription)
        }
    }
}

private final class RetryIfSubscription<Upstream, Context, S>: Subscription, Subscriber
where
    Upstream: Publisher,
    Context: Scheduler,
    S: Subscriber,
    S.Input == Upstream.Output,
    S.Failure == Upstream.Failure
{
    typealias Input = Upstream.Output
    typealias Failure = Upstream.Failure

    private enum State {
        case waitingForSubscription(S)
        case retrying(S)
        case ready(S, Subscription)
        case completed

        var subscriber: S? {
            switch self {
            case let .waitingForSubscription(sub),
                 let .retrying(sub),
                 let .ready(sub, _):
                return sub

            case .completed:
                return nil
            }
        }

        var subscription: Subscription? {
            switch self {
            case let .ready(_, subscription):
                return subscription

            case .waitingForSubscription, .retrying, .completed:
                return nil
            }
        }
    }

    private let upstream: Upstream
    private let predicate: (Failure) -> Bool
    private let interval: (Int) -> Context.SchedulerTimeType.Stride
    private let tolerance: Context.SchedulerTimeType.Stride
    private let scheduler: Context
    private let options: Context.SchedulerOptions?

    private var retries: Int = 0
    private var demand: Subscribers.Demand = .none

    private var state: State
    private let lock = RecursiveLock()

    init(
        upstream: Upstream,
        retryIf predicate: @escaping (Failure) -> Bool,
        interval: @escaping (Int) -> Context.SchedulerTimeType.Stride,
        tolerance: Context.SchedulerTimeType.Stride,
        scheduler: Context,
        options: Context.SchedulerOptions? = nil,
        subscriber: S
    ) {
        self.upstream = upstream
        self.predicate = predicate
        self.interval = interval
        self.tolerance = tolerance
        self.scheduler = scheduler
        self.options = options
        self.state = .waitingForSubscription(subscriber)
    }

    deinit {
        cancel()
    }

    func cancel() {
        let subscription: Subscription? = lock.locked {
            let sub = state.subscription
            state = .completed
            return sub
        }
        subscription?.cancel()
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        let subscription: Subscription? = lock.locked {
            self.demand += demand
            return state.subscription
        }
        subscription?.request(demand)
    }

    func receive(subscription: Subscription) {
        let subscriberAndDemand: (S?, Subscribers.Demand)? = lock.locked {
            switch state {
            // If this is the initial call to this method, we need to
            // call `subscriber.receive(subscription:)`, which is why
            // we return `subscriber` here.
            case let .waitingForSubscription(subscriber):
                state = .ready(subscriber, subscription)
                return (subscriber, demand)

            // If we are retrying after receiving a failure, we do not
            // want to call `subscriber.receive(subscription:)`, which
            // is why we do not return `subscriber` here.
            case let .retrying(subscriber):
                state = .ready(subscriber, subscription)
                return (nil, demand)

            case .ready, .completed:
                return nil
            }
        }

        guard let (subscriber, demand) = subscriberAndDemand
        else { return subscription.cancel() }

        subscriber?.receive(subscription: self)
        guard demand > .none else { return }
        subscription.request(demand)
    }

    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        let subs: (S, Subscription)? = lock.locked {
            guard demand > .none, case let .ready(subscriber, subscription) = state
            else { return nil }
            demand -= 1
            retries = 0
            return (subscriber, subscription)
        }

        guard let (subscriber, subscription) = subs else { return .none }
        let newDemand = subscriber.receive(input)
        guard newDemand > .none else { return .none }
        lock.locked { demand += newDemand }
        subscription.request(newDemand)
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        switch completion {
        case .finished:
            complete(with: .finished)

        case let .failure(error):
            let shouldRetry = predicate(error)
            guard shouldRetry else {
                complete(with: .failure(error))
                return
            }

            let _count: Int? = lock.locked {
                guard case let .ready(subscriber, _) = state
                else { return nil }
                state = .retrying(subscriber)
                retries += 1
                return retries
            }
            guard let count = _count else { return complete(with: completion) }

            scheduler.schedule(
                after: scheduler.now.advanced(by: interval(count)),
                tolerance: tolerance,
                options: options
            ) {
                // We need to retain `self` strongly in this block
                // or else we could be deallocated.
                self.upstream.subscribe(self)
            }
        }
    }

    private func complete(with completion: Subscribers.Completion<Failure>) {
        let subscriberAndSubscription: (S?, Subscription?) = lock.locked {
            let oldState = state
            state = .completed
            return (oldState.subscriber, oldState.subscription)
        }

        if let subscription = subscriberAndSubscription.1 {
            subscription.cancel()
        }

        if let subscriber = subscriberAndSubscription.0 {
            subscriber.receive(completion: completion)
        }
    }
}

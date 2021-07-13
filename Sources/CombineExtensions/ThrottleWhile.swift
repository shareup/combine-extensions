import Foundation
import Combine
import Synchronized

extension Publisher {
    public func throttle<Regulator: Publisher>(
        while regulator: Regulator,
        latest: Bool = true
    ) -> Publishers.ThrottleWhile<Self, Regulator> {
        Publishers.ThrottleWhile(upstream: self, regulator: regulator, latest: latest)
    }
}

extension Publishers {
    public struct ThrottleWhile<
        Upstream: Publisher,
        Regulator: Publisher
    >: Publisher where Regulator.Output == Bool {

        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream
        private let regulator: Regulator
        private let latest: Bool

        public init(upstream: Upstream, regulator: Regulator, latest: Bool) {
            self.upstream = upstream
            self.regulator = regulator
            self.latest = latest
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where S.Input == Output, S.Failure == Failure {
            let subscription = ThrottleWhileSubscription(
                upstream: upstream,
                regulator: regulator,
                latest: latest,
                subscriber: subscriber
            )
            upstream.receive(subscriber: subscription)
        }
    }
}

private final class ThrottleWhileSubscription<Upstream, Regulator, S>: Subscription, Subscriber
where
    Upstream: Publisher,
    Regulator: Publisher,
    S: Subscriber,
    S.Input == Upstream.Output,
    S.Failure == Upstream.Failure,
    Regulator.Output == Bool
{
    typealias Input = Upstream.Output
    typealias Failure = Upstream.Failure

    private enum State {
        case waitingForSubscription(S)
        case ready(S, Subscription, Input?)
        case completed

        var subscriber: S? {
            switch self {
            case let .waitingForSubscription(sub), let .ready(sub, _, _):
                return sub

            case .completed:
                return nil
            }
        }

        var subscription: Subscription? {
            switch self {
            case let .ready(_, subscription, _):
                return subscription

            case .waitingForSubscription, .completed:
                return nil
            }
        }

        var valueToPublish: Input? {
            switch self {
            case let .ready(_, _, value):
                return value

            case .waitingForSubscription, .completed:
                return nil
            }
        }
    }

    private let upstream: Upstream
    private let regulator: Regulator
    private let latest: Bool

    private var demand: Subscribers.Demand = .none
    private var regulatorSubscription: AnyCancellable?
    private var isThrottled: Bool = true

    private var state: State
    private let lock = RecursiveLock()

    init(
        upstream: Upstream,
        regulator: Regulator,
        latest: Bool,
        subscriber: S
    ) {
        self.upstream = upstream
        self.regulator = regulator
        self.latest = latest
        state = .waitingForSubscription(subscriber)

        self.regulatorSubscription = regulator.sink(
            receiveValue: onReceiveRegulatorValue,
            receiveCompletion: onReceiveRegulatorCompletion
        )
    }

    deinit {
        cancel()
    }

    func cancel() {
        complete(with: .finished)
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        let subscription: Subscription? = lock.locked {
            self.demand += demand
            return state.subscription
        }
        subscription?.request(.unlimited)
    }

    func receive(subscription: Subscription) {
        let subscriber: S? = lock.locked {
            switch state {
            case let .waitingForSubscription(subscriber):
                state = .ready(subscriber, subscription, nil)
                return subscriber

            case .ready, .completed:
                subscription.cancel()
                return nil
            }
        }

        subscriber?.receive(subscription: self)
    }

    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        let shouldPublish: Bool = lock.locked {
            switch state {
            case let .ready(subscriber, subscription, previousInput):
                guard let previousInput = previousInput else {
                    state = .ready(subscriber, subscription, input)
                    return true
                }
                state = .ready(subscriber, subscription, latest ? input : previousInput)
                return true

            case .waitingForSubscription, .completed:
                return false
            }
        }

        guard shouldPublish else { return .none }
        
        publishIfPossible()
        return .none
    }

    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        complete(with: completion)
    }

    private func publishIfPossible() {
        let subAndOutput: (S, Input)? =  lock.locked {
            guard demand > .none, !isThrottled else { return nil }
            guard case let .ready(subscriber, subscription, _output) = state,
                  let output = _output
            else { return nil }

            state = .ready(subscriber, subscription, nil)
            demand -= 1
            return (subscriber, output)
        }

        guard let (sub, output) = subAndOutput else { return }
        let newDemand = sub.receive(output)

        guard newDemand > .none else { return }
        lock.locked { demand += newDemand }
    }

    private func complete(with completion: Subscribers.Completion<Failure>) {
        let (subscriber, subscription, regulatorSub): (S?, Subscription?, AnyCancellable?) =
            lock.locked {
                let oldState = self.state
                let regulatorSub = self.regulatorSubscription

                self.state = .completed
                self.isThrottled = true
                self.regulatorSubscription = nil

                return (oldState.subscriber, oldState.subscription, regulatorSub)
            }

        subscription?.cancel()
        regulatorSub?.cancel()
        subscriber?.receive(completion: completion)
    }

    private var onReceiveRegulatorValue: (Bool) -> Void {
        { [weak self] isThrottled in
            guard let self = self else { return }
            self.lock.locked { self.isThrottled = isThrottled }
            self.publishIfPossible()
        }
    }

    private var onReceiveRegulatorCompletion: (Subscribers.Completion<Regulator.Failure>) -> Void {
        { [weak self] _ in self?.complete(with: .finished) }
    }
}


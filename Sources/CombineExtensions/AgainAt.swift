import Combine
import Foundation
import Synchronized

public extension Publisher {
    func againAt<Context: Scheduler>(
        scheduler: Context,
        options: Context.SchedulerOptions? = nil
    ) -> Publishers.AgainAt<Self, Context> {
        Publishers.AgainAt(upstream: self, scheduler: scheduler, options: options)
    }
}

public extension Publishers {
    struct AgainAt<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = (Upstream.Output, Timer)
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream
        private let scheduler: Context
        private let options: Context.SchedulerOptions?

        public init(
            upstream: Upstream,
            scheduler: Context,
            options: Context.SchedulerOptions?
        ) {
            self.upstream = upstream
            self.scheduler = scheduler
            self.options = options
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where S.Input == Output, S.Failure == Failure {
            let subscription = AgainAtSubscription<Upstream, Context, S>(
                scheduler: scheduler,
                options: options,
                subscriber: subscriber
            )

            upstream
                .receive(on: scheduler, options: options)
                .subscribe(subscription)
        }
    }
}

public extension Publishers.AgainAt {
    final class Timer: @unchecked Sendable {
        public let now: Context.SchedulerTimeType

        private let scheduler: Context
        private let onRepublishAt: @Sendable (Context.SchedulerTimeType) -> Void

        fileprivate init(
            now: Context.SchedulerTimeType,
            scheduler: Context,
            onRepublishAt: @escaping @Sendable (Context.SchedulerTimeType) -> Void
        ) {
            self.now = now
            self.scheduler = scheduler
            self.onRepublishAt = onRepublishAt
        }

        public func republish(at time: Context.SchedulerTimeType) {
            onRepublishAt(time)
        }

        public func time(at date: Date) -> Context.SchedulerTimeType {
            let nanoseconds = date.timeIntervalSinceNow.nanoseconds
            return scheduler.now.advanced(by: .nanoseconds(nanoseconds))
        }
    }
}

private final class AgainAtSubscription<Upstream, Context, Downstream>:
    Subscription,
    Subscriber,
    @unchecked Sendable
    where
    Upstream: Publisher,
    Context: Scheduler,
    Downstream: Subscriber,
    Downstream.Input == Publishers.AgainAt<Upstream, Context>.Output,
    Downstream.Failure == Upstream.Failure
{
    typealias Input = Upstream.Output
    typealias Failure = Upstream.Failure

    private final class RepublishToken {}

    private struct State {
        var downstream: Downstream?
        var upstream: Subscription?
        var demand: Subscribers.Demand = .none

        var latestOutput: Upstream.Output?
        var pendingOutput: Upstream.Output?

        var activeRepublish: RepublishToken?
        var pendingCompletion: Subscribers.Completion<Failure>?

        var isDraining = false
        var isDrainScheduled = false
    }

    private enum DrainAction {
        case completion(Downstream, Subscribers.Completion<Failure>)
        case stop
        case value(Downstream, Upstream.Output)
    }

    private let scheduler: Context
    private let options: Context.SchedulerOptions?
    private let state: Locked<State>

    init(
        scheduler: Context,
        options: Context.SchedulerOptions?,
        subscriber: Downstream
    ) {
        self.scheduler = scheduler
        self.options = options
        state = Locked(State(downstream: subscriber))
    }

    deinit {
        cancel()
    }

    func receive(subscription: Subscription) {
        let downstream = state.access { state -> Downstream? in
            guard state.downstream != nil,
                  state.upstream == nil
            else { return nil }
            state.upstream = subscription
            return state.downstream
        }

        guard let downstream else {
            subscription.cancel()
            return
        }

        downstream.receive(subscription: self)

        let shouldRequest = state.access { state in
            state.downstream != nil && state.upstream != nil
        }

        if shouldRequest {
            subscription.request(.unlimited)
        }
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }

        state.access { state in
            guard state.downstream != nil else { return }
            state.demand += demand
        }

        scheduleDrain()
    }

    func cancel() {
        let upstream = state.access { state -> Subscription? in
            let upstream = state.upstream

            state.downstream = nil
            state.upstream = nil
            state.latestOutput = nil
            state.pendingOutput = nil
            state.activeRepublish = nil
            state.pendingCompletion = nil
            state.isDraining = false
            state.isDrainScheduled = false

            return upstream
        }

        upstream?.cancel()
    }

    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        state.access { state in
            guard state.downstream != nil, state.pendingCompletion == nil else {
                return
            }

            state.latestOutput = input
            state.pendingOutput = input
        }

        drain()
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        state.access { state in
            guard state.downstream != nil, state.pendingCompletion == nil else {
                return
            }

            state.pendingCompletion = completion
            state.activeRepublish = nil
            state.latestOutput = nil
        }

        drain()
    }

    private func republish(at time: Context.SchedulerTimeType) {
        let token = RepublishToken()

        let shouldSchedule = state.access { state in
            guard
                state.downstream != nil,
                state.pendingCompletion == nil,
                state.latestOutput != nil
            else {
                return false
            }

            state.activeRepublish = token
            return true
        }

        guard shouldSchedule else { return }

        scheduler.schedule(
            after: time,
            tolerance: scheduler.minimumTolerance,
            options: options
        ) { [weak self] in
            self?.fire(token)
        }
    }

    private func fire(_ token: RepublishToken) {
        state.access { state in
            guard state.downstream != nil,
                  state.pendingCompletion == nil,
                  state.activeRepublish === token,
                  let latestOutput = state.latestOutput
            else { return }

            state.activeRepublish = nil
            state.pendingOutput = latestOutput
        }

        drain()
    }

    private func drain() {
        let shouldDrain = state.access { state in
            state.isDrainScheduled = false

            guard state.downstream != nil,
                  !state.isDraining,
                  hasWork(state)
            else { return false }

            state.isDraining = true
            return true
        }

        guard shouldDrain else { return }

        while true {
            let action = state.access { state -> DrainAction in
                guard let downstream = state.downstream else {
                    state.isDraining = false
                    return .stop
                }

                if let output = state.pendingOutput, state.demand > .none {
                    state.pendingOutput = nil
                    state.demand -= .max(1)
                    return .value(downstream, output)
                }

                if let completion = state.pendingCompletion {
                    state.downstream = nil
                    state.upstream = nil
                    state.latestOutput = nil
                    state.pendingOutput = nil
                    state.activeRepublish = nil
                    state.isDraining = false
                    state.isDrainScheduled = false
                    return .completion(downstream, completion)
                }

                state.isDraining = false
                return .stop
            }

            switch action {
            case let .completion(downstream, completion):
                downstream.receive(completion: completion)
                return

            case .stop:
                return

            case let .value(downstream, output):
                let timer = Publishers.AgainAt<Upstream, Context>.Timer(
                    now: scheduler.now,
                    scheduler: scheduler,
                    onRepublishAt: { [weak self] time in
                        self?.republish(at: time)
                    }
                )

                let newDemand = downstream.receive((output, timer))

                if newDemand > .none {
                    state.access { state in
                        if state.downstream != nil {
                            state.demand += newDemand
                        }
                    }
                }
            }
        }
    }

    private func hasWork(_ state: State) -> Bool {
        (state.pendingOutput != nil && state.demand > .none)
            || state.pendingCompletion != nil
    }

    private func scheduleDrain() {
        let shouldSchedule = state.access { state in
            guard state.downstream != nil,
                  !state.isDraining,
                  !state.isDrainScheduled,
                  hasWork(state)
            else { return false }

            state.isDrainScheduled = true
            return true
        }

        if shouldSchedule {
            scheduler.schedule(options: options) { [weak self] in
                self?.drain()
            }
        }
    }
}

private extension TimeInterval {
    var nanoseconds: Int {
        guard self > 0 else { return 0 }
        let nanoseconds = self * 1_000_000_000
        guard nanoseconds < Double(maxNanoseconds) else {
            return maxNanoseconds
        }
        return Int(nanoseconds)
    }
}

private let maxNanoseconds = Int.max - 1024

import Foundation
import Combine
import Synchronized

extension Publisher {
    public func measuredSink(
        initialDemand: Subscribers.Demand = .none,
        receiveValue: @escaping (Output) -> Subscribers.Demand,
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
    ) -> DemandCancellable<Output, Failure> {
        let sink = MeasuredSink<Output, Failure>(
            initialDemand: initialDemand,
            receiveValue: receiveValue,
            receiveCompletion: receiveCompletion
        )
        subscribe(sink)
        return DemandCancellable(sink)
    }
}

extension Publisher where Failure == Never {
    public func measuredSink(
        initialDemand: Subscribers.Demand = .none,
        receiveValue: @escaping (Output) -> Subscribers.Demand
    ) -> DemandCancellable<Output, Failure> {
        let sink = MeasuredSink<Output, Failure>(
            initialDemand: initialDemand,
            receiveValue: receiveValue,
            receiveCompletion: { _ in }
        )
        subscribe(sink)
        return DemandCancellable(sink)
    }
}

public final class DemandCancellable<Input, Failure>: Cancellable where Failure: Error {
    private let sink: MeasuredSink<Input, Failure>

    init(_ sink: MeasuredSink<Input, Failure>) {
        self.sink = sink
    }

    public func request(demand: Subscribers.Demand) {
        sink.request(demand: demand)
    }

    public func cancel() {
        sink.cancel()
    }
}

/// A simple subscriber that requests a custom number of values upon subscription
/// and after receiving new values.
final class MeasuredSink<Input, Failure>: Subscriber, Cancellable where Failure: Error {
    private enum State {
        case unsubscribed(Subscribers.Demand)
        case subscribed(Subscription)
        case finished
    }

    private let onReceiveValue: (Input) -> Subscribers.Demand
    private let onReceiveCompletion: (Subscribers.Completion<Failure>) -> Void

    private var state: State
    private let lock = RecursiveLock()

    init(
        initialDemand: Subscribers.Demand,
        receiveValue: @escaping (Input) -> Subscribers.Demand,
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
    ) {
        state = .unsubscribed(initialDemand)
        onReceiveValue = receiveValue
        onReceiveCompletion = receiveCompletion
    }

    func request(demand: Subscribers.Demand) {
        guard demand > .none else { return }

        lock.locked {
            switch state {
            case let .unsubscribed(previousDemand):
                state = .unsubscribed(previousDemand + demand)

            case let .subscribed(subscription):
                subscription.request(demand)

            case .finished:
                break
            }
        }
    }

    func receive(subscription: Subscription) {
        let (didSet, demand): (Bool, Subscribers.Demand) = lock.locked {
            guard case let .unsubscribed(demand) = state else {
                return (false, .none)
            }
            state = .subscribed(subscription)
            return (true, demand)
        }

        if didSet {
            request(demand: demand)
        } else {
            subscription.cancel()
        }
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        let shouldReceive: Bool = lock.locked {
            switch state {
            case .unsubscribed, .subscribed:
                return true
            case .finished:
                return false
            }
        }

        guard shouldReceive else { return .none }
        return onReceiveValue(input)
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        onReceiveCompletion(completion)
        lock.locked { state = .finished }
    }

    func cancel() {
        let sub: Subscription? = lock.locked {
            switch state {
            case let .subscribed(subscription):
                state = .finished
                return subscription

            case .unsubscribed, .finished:
                state = .finished
                return nil
            }
        }

        sub?.cancel()
    }
}

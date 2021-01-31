import Combine
import Foundation
import Synchronized

/// `BufferPassthroughSubject` buffers all values until it has been subscribed
/// to. At that point, all the buffered values will be sent to the `Subscriber`.
/// Any additional `Subscriber`s will not receive the previously buffered
/// values.
public final class BufferPassthroughSubject<Output, Failure: Error>: Subject {
    private enum State {
        case buffering([Output])
        case passingThrough
        case bufferingAfterReceivingCompletion([Output], Subscribers.Completion<Failure>)
        case completed
    }

    private let subject = PassthroughSubject<Output, Failure>()
    private let lock = RecursiveLock()
    private var state: State = .buffering([])

    public init() {}

    public func send(_ value: Output) {
        locked {
            switch state {
            case var .buffering(buffer):
                buffer.append(value)
                state = .buffering(buffer)
                return nil
            case .passingThrough:
                return { self.subject.send(value) }
            case .bufferingAfterReceivingCompletion:
                // Do not buffer any more values after receiving completion
                return nil
            case .completed:
                return nil
            }
        }
    }

    public func send(completion: Subscribers.Completion<Failure>) {
        locked {
            switch state {
            case let .buffering(buffer):
                state = .bufferingAfterReceivingCompletion(buffer, completion)
                return nil
            case .passingThrough:
                state = .completed
                return { self.subject.send(completion: completion) }
            case .bufferingAfterReceivingCompletion:
                return nil
            case .completed:
                return { self.subject.send(completion: completion) }
            }
        }
    }

    public func send(subscription: Subscription) {
        locked {
            switch state {
            case .buffering:
                return { self.subject.send(subscription: subscription) }
            case .passingThrough:
                return { self.subject.send(subscription: subscription) }
            case .bufferingAfterReceivingCompletion:
                return { self.subject.send(subscription: subscription) }
            case .completed:
                return { self.subject.send(subscription: subscription) }
            }
        }
    }

    public func receive<S: Subscriber>(
        subscriber: S
    ) where Failure == S.Failure, Output == S.Input {
        locked {
            switch state {
            case let .buffering(buffer):
                subject.receive(subscriber: subscriber)
                buffer.forEach { self.subject.send($0) }
                self.state = .passingThrough
                return nil
            case .passingThrough:
                return { self.subject.receive(subscriber: subscriber) }
            case let .bufferingAfterReceivingCompletion(buffer, completion):
                subject.receive(subscriber: subscriber)
                buffer.forEach { self.subject.send($0) }
                state = .completed
                return { self.subject.send(completion: completion) }
            case .completed:
                return { self.subject.receive(subscriber: subscriber) }
            }
        }
    }

    private func locked(_ block: () -> (() -> Void)?) {
        let action = lock.locked { block() }
        action?()
    }
}

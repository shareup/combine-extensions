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
        lock.locked {
            switch state {
            case var .buffering(buffer):
                buffer.append(value)
                state = .buffering(buffer)
            case .passingThrough:
                self.subject.send(value)
            case .bufferingAfterReceivingCompletion:
                // Do not buffer any more values after receiving completion
                break
            case .completed:
                break
            }
        }
    }

    public func send(completion: Subscribers.Completion<Failure>) {
        lock.locked {
            switch state {
            case let .buffering(buffer):
                state = .bufferingAfterReceivingCompletion(buffer, completion)
            case .passingThrough:
                state = .completed
                self.subject.send(completion: completion)
            case .bufferingAfterReceivingCompletion:
                break
            case .completed:
                self.subject.send(completion: completion)
            }
        }
    }

    public func send(subscription: Subscription) {
        lock.locked {
            switch state {
            case .buffering:
                self.subject.send(subscription: subscription)
            case .passingThrough:
                self.subject.send(subscription: subscription)
            case .bufferingAfterReceivingCompletion:
                self.subject.send(subscription: subscription)
            case .completed:
                self.subject.send(subscription: subscription)
            }
        }
    }

    public func receive<S: Subscriber>(
        subscriber: S
    ) where Failure == S.Failure, Output == S.Input {
        lock.locked {
            switch state {
            case let .buffering(buffer):
                subject.receive(subscriber: subscriber)
                buffer.forEach { self.subject.send($0) }
                self.state = .passingThrough
            case .passingThrough:
                self.subject.receive(subscriber: subscriber)
            case let .bufferingAfterReceivingCompletion(buffer, completion):
                subject.receive(subscriber: subscriber)
                buffer.forEach { self.subject.send($0) }
                state = .completed
                self.subject.send(completion: completion)
            case .completed:
                self.subject.receive(subscriber: subscriber)
            }
        }
    }
}

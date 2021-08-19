import Foundation
import Combine

extension ConnectablePublisher {
    public func eraseToAnyConnectablePublisher() -> AnyConnectablePublisher<Output, Failure> {
        AnyConnectablePublisher(self)
    }
}

public struct AnyConnectablePublisher<Output, Failure: Error>: ConnectablePublisher {
    private let publisher: _Box<Output, Failure>

    fileprivate init<P: ConnectablePublisher>(
        _ publisher: P
    ) where P.Output == Output, P.Failure == Failure {
        self.publisher = Box(publisher)
    }

    public func receive<S: Subscriber>(
        subscriber: S
    ) where S.Failure == Failure, S.Input == Output {
        publisher.receive(subscriber: subscriber)
    }

    public func connect() -> Cancellable {
        publisher.connect()
    }
}

private class _Box<Output, Failure: Error>: ConnectablePublisher {
    init() {}

    func receive<S: Subscriber>(
        subscriber: S
    ) where S.Failure == Failure, S.Input == Output {
        preconditionFailure()
    }

    func connect() -> Cancellable {
        preconditionFailure()
    }
}

private final class Box<Wrapped: ConnectablePublisher>: _Box<Wrapped.Output, Wrapped.Failure> {
    fileprivate let wrapped: Wrapped

    fileprivate init(_ publisher: Wrapped) {
        wrapped = publisher
    }

    fileprivate override func receive<S: Subscriber>(
        subscriber: S
    ) where S.Failure == Failure, S.Input == Output {
        wrapped.receive(subscriber: subscriber)
    }

    fileprivate override func connect() -> Cancellable {
        wrapped.connect()
    }
}

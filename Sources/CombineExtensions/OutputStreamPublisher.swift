import Combine
import Foundation
import Synchronized

public extension Publisher where Output == [UInt8], Failure == Error {
    func stream(
        toBuffer buffer: UnsafeMutablePointer<UInt8>,
        capacity: Int
    ) -> Publishers.OutputStream<Self> {
        Publishers.OutputStream(upstream: self, buffer: buffer, capacity: capacity)
    }

    func stream(
        toURL url: URL,
        append: Bool
    ) -> Publishers.OutputStream<Self> {
        Publishers.OutputStream(upstream: self, url: url, append: append)
    }
}

public extension Publishers {
    struct OutputStream<Upstream: Publisher>: Publisher
        where Upstream.Output == [UInt8], Upstream.Failure == Error
    {
        public typealias Output = Int
        public typealias Failure = Error

        private enum StreamType {
            case buffer(UnsafeMutablePointer<UInt8>, Int)
            case url(URL, Bool)
        }

        private let upstream: Upstream
        private let streamType: StreamType

        public init(
            upstream: Upstream,
            buffer: UnsafeMutablePointer<UInt8>,
            capacity: Int
        ) {
            self.upstream = upstream
            streamType = .buffer(buffer, capacity)
        }

        public init(
            upstream: Upstream,
            url: URL,
            append: Bool
        ) {
            self.upstream = upstream
            streamType = .url(url, append)
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Output == S.Input, Failure == S.Failure {
            let subscription: OutputStreamSubscription<S>

            switch streamType {
            case let .buffer(buffer, capacity):
                subscription = OutputStreamSubscription(
                    toBuffer: buffer,
                    capacity: capacity,
                    subscriber: subscriber
                )

            case let .url(url, append):
                subscription = OutputStreamSubscription(
                    toURL: url,
                    append: append,
                    subscriber: subscriber
                )
            }

            upstream.subscribe(subscription)
        }
    }
}

private final class OutputStreamSubscription<S: Subscriber>: Subscription, Subscriber
    where S.Input == Int, S.Failure == Error
{
    typealias Input = [UInt8]
    typealias Failure = Error

    private var state: StreamState<S>
    private let lock = RecursiveLock()

    init(
        toBuffer buffer: UnsafeMutablePointer<UInt8>,
        capacity: Int,
        subscriber: S
    ) {
        let stream = OutputStream(toBuffer: buffer, capacity: capacity)
        state = .awaitingSubscription(stream, subscriber)
    }

    init(
        toURL url: URL,
        append: Bool,
        subscriber: S
    ) {
        if let stream = OutputStream(url: url, append: append) {
            state = .awaitingSubscription(stream, subscriber)
        } else {
            state = .error(StreamError.couldNotLoadFileAtURL(url))
        }
    }

    deinit {
        cancel()
    }

    var description: String { "Stream" }

    func cancel() {
        let (outputStream, subscription): (OutputStream?, Subscription?) = lock.locked {
            switch state {
            case let .awaitingSubscription(stream, _):
                state = .finished
                return (stream, nil)

            case let .streaming(stream, subscription, _):
                state = .finished
                return (stream, subscription)

            case .error, .finished:
                return (nil, nil)
            }
        }

        subscription?.cancel()
        outputStream?.close()
    }

    func receive(subscription: Subscription) {
        let streamAndSubscriber: (OutputStream, S)? = lock.locked {
            switch state {
            case let .awaitingSubscription(stream, subscriber):
                state = .streaming(stream, subscription, subscriber)
                return (stream, subscriber)

            case .streaming, .error, .finished:
                return nil
            }
        }

        guard let (stream, subscriber) = streamAndSubscriber else {
            subscription.cancel()
            return
        }

        stream.open()
        guard stream.hasSpaceAvailable else {
            if let error = stream.streamError {
                lock.locked { state = .error(error) }
                subscriber.receive(completion: .failure(error))
                subscription.cancel()
            } else {
                lock.locked { state = .finished }
                subscriber.receive(completion: .failure(StreamError.noSpaceAvailable))
                subscription.cancel()
            }
            stream.close()
            return
        }

        subscriber.receive(subscription: self)
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        guard let subscription = (lock.locked { state.subscription })
        else { return }
        subscription.request(demand)
    }

    func receive(_ input: [UInt8]) -> Subscribers.Demand {
        let streamAndSubscriber: (OutputStream, S)? = lock.locked {
            switch state {
            case let .streaming(stream, _, subscriber):
                return (stream, subscriber)
            case .awaitingSubscription, .error, .finished:
                return nil
            }
        }
        guard let (stream, subscriber) = streamAndSubscriber else { return .none }

        let result = stream.write(input, maxLength: input.count)

        switch result {
        case 0:
            complete(with: .finished)
            return .none

        case -1:
            let error = stream.streamError ?? StreamError.unknown
            complete(with: .failure(error))
            return .none

        default:
            return subscriber.receive(result)
        }
    }

    func receive(completion: Subscribers.Completion<Error>) {
        complete(with: completion)
    }

    private func complete(with completion: Subscribers.Completion<Error>) {
        let (stream, subscription, subscriber) = lock.locked
            { () -> (OutputStream?, Subscription?, S?) in
                switch state {
                case let .awaitingSubscription(stream, subscriber):
                    state = StreamState(completion)
                    return (stream, nil, subscriber)

                case let .streaming(stream, subscription, subscriber):
                    state = StreamState(completion)
                    return (stream, subscription, subscriber)

                case .finished, .error:
                    return (nil, nil, nil)
                }
            }

        stream?.close()
        subscription?.cancel()
        subscriber?.receive(completion: completion)
    }
}

private enum StreamState<S: Subscriber> {
    case awaitingSubscription(OutputStream, S)
    case streaming(OutputStream, Subscription, S)
    case error(Error)
    case finished

    init(_ completion: Subscribers.Completion<Error>) {
        switch completion {
        case .finished:
            self = .finished
        case let .failure(error):
            self = .error(error)
        }
    }

    var isStreaming: Bool {
        switch self {
        case .streaming:
            return true
        case .awaitingSubscription, .error, .finished:
            return false
        }
    }

    var subscription: Subscription? {
        switch self {
        case let .streaming(_, subscription, _):
            return subscription
        case .awaitingSubscription, .error, .finished:
            return nil
        }
    }

    var subscriber: S? {
        switch self {
        case let .awaitingSubscription(_, subscriber):
            return subscriber
        case let .streaming(_, _, subscriber):
            return subscriber
        case .error, .finished:
            return nil
        }
    }
}

private enum StreamError: Error {
    case unknown
    case noSpaceAvailable
    case couldNotLoadFileAtURL(URL)
}

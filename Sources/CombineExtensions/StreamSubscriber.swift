import Combine
import Foundation
import Synchronized

public extension Publisher where Output == [UInt8], Failure == Error {
    func stream(
        toBuffer buffer: UnsafeMutablePointer<UInt8>,
        capacity: Int,
        receiveValue: @escaping (Int) -> Void,
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
    ) -> AnyCancellable {
        let subscriber = Subscribers.Stream(
            toBuffer: buffer,
            capacity: capacity,
            receiveValue: receiveValue,
            receiveCompletion: receiveCompletion
        )
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }

    func stream(
        toURL url: URL,
        append: Bool,
        receiveValue: @escaping (Int) -> Void,
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
    ) -> AnyCancellable {
        let subscriber = Subscribers.Stream(
            toURL: url,
            append: append,
            receiveValue: receiveValue,
            receiveCompletion: receiveCompletion
        )
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}

public extension Subscribers {
    final class Stream: Subscriber, Cancellable, CustomStringConvertible {
        public typealias Input = [UInt8]
        public typealias Failure = Error

        private let onWriteBytes: (Int) -> Void
        private let onCompletion: (Subscribers.Completion<Failure>) -> Void
        
        private var state: StreamState
        private let lock = Lock()
        
        public init(
            toBuffer buffer: UnsafeMutablePointer<UInt8>,
            capacity: Int,
            receiveValue: @escaping (Int) -> Void,
            receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
        ) {
            self.onWriteBytes = receiveValue
            self.onCompletion = receiveCompletion

            let stream = OutputStream(toBuffer: buffer, capacity: capacity)
            state = .awaitingSubscription(stream)
        }
        
        public init(
            toURL url: URL,
            append: Bool,
            receiveValue: @escaping (Int) -> Void,
            receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void
        ) {
            self.onWriteBytes = receiveValue
            self.onCompletion = receiveCompletion

            if let stream = OutputStream(url: url, append: append) {
                state = .awaitingSubscription(stream)
            } else {
                state = .error(StreamError.couldNotLoadFileAtURL(url))
            }
        }
        
        deinit {
            cancel()
        }

        public var description: String { "Stream" }
        
        public func cancel() {
            let (outputStream, subscription): (OutputStream?, Subscription?) = lock.locked {
                switch state {
                case let .awaitingSubscription(stream):
                    state = .finished
                    return (stream, nil)

                case let .streaming(stream, subscription):
                    state = .finished
                    return (stream, subscription)

                case .error, .finished:
                    return (nil, nil)
                }
            }

            outputStream?.close()
            subscription?.cancel()
        }
        
        public func receive(subscription: Subscription) {
            let validSub: Subscription? = lock.locked {
                switch state {
                case let .awaitingSubscription(stream):
                    stream.open()
                    guard stream.hasSpaceAvailable else {
                        if let error = stream.streamError {
                            state = .error(error)
                            subscription.cancel()
                            return nil
                        } else {
                            state = .finished
                            subscription.cancel()
                            return nil
                        }
                    }
                    state = .streaming(stream, subscription)
                    return subscription

                case .streaming, .error, .finished:
                    subscription.cancel()
                    return nil
                }
            }
            
            validSub?.request(newDemand)
        }
        
        public func receive(_ input: [UInt8]) -> Subscribers.Demand {
            guard let stream = lock.locked({ state.openStream })
            else { return .none }
            
            let result = stream.write(input, maxLength: input.count)
            
            switch result {
            case 0:
                stream.close()
                let shouldCallOnCompletion: Bool = lock.locked {
                    let oldState = state
                    state = .finished
                    return oldState.isStreaming
                }
                if shouldCallOnCompletion {
                    onCompletion(.finished)
                }
                return .none
                
            case -1:
                stream.close()
                let error = stream.streamError ?? StreamError.unknown
                let shouldCallOnCompletion: Bool = lock.locked {
                    let oldState = state
                    state = .error(error)
                    return oldState.isStreaming
                }
                if shouldCallOnCompletion {
                    onCompletion(.failure(error))
                }
                return .none
                
            default:
                onWriteBytes(result)
                return stream.hasSpaceAvailable ? .max(1) : .none
            }
        }
        
        public func receive(completion: Subscribers.Completion<Error>) {
            let shouldCallOnCompletion: Bool = lock.locked {
                switch state {
                case let .awaitingSubscription(stream):
                    // We never opened it, but calling `close()` on an unopened
                    // stream doesn't appear to cause any problems. So, we do
                    // it just to be safe.
                    stream.close()
                    state = StreamState(completion)
                    return false
                    
                case let .streaming(stream, _):
                    stream.close()
                    state = StreamState(completion)
                    return true

                case .finished, .error:
                    return false
                }
            }

            guard shouldCallOnCompletion else { return }
            onCompletion(completion)
        }

        private var newDemand: Subscribers.Demand {
            guard let stream = lock.locked({ state.openStream })
            else { return .none }

            return stream.hasSpaceAvailable ? .max(1) : .none
        }
    }
}


private enum StreamState {
    case awaitingSubscription(OutputStream)
    case streaming(OutputStream, Subscription)
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
        case let .streaming(_, subscription):
            return subscription
        case .awaitingSubscription, .error, .finished:
            return nil
        }
    }

    var openStream: OutputStream? {
        switch self {
        case .awaitingSubscription, .error, .finished:
            return nil
        case let .streaming(stream, _):
            return stream
        }
    }
}

private enum StreamType {
    case buffer(UnsafeMutablePointer<UInt8>)
    case url(URL)
}

private enum StreamError: Error {
    case unknown
    case couldNotLoadFileAtURL(URL)
}

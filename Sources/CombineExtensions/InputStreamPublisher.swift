import Combine
import Foundation
import Synchronized

public extension Data {
    func publisher(maxChunkSize: Int) -> Publishers.InputStream {
        Publishers.InputStream(data: self, maxChunkSize: maxChunkSize)
    }
}

public extension URL {
    func publisher(maxChunkSize: Int) -> Publishers.InputStream {
        Publishers.InputStream(url: self, maxChunkSize: maxChunkSize)
    }
}

public extension Publishers {
    struct InputStream: Publisher {
        public typealias Output = [UInt8]
        public typealias Failure = Error

        private let streamType: StreamType
        private let maxChunkSize: Int

        public init(url: URL, maxChunkSize: Int) {
            streamType = .url(url)
            self.maxChunkSize = maxChunkSize
        }

        public init(data: Data, maxChunkSize: Int) {
            streamType = .data(data)
            self.maxChunkSize = maxChunkSize
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Failure == S.Failure, Output == S.Input {
            let subscription = InputStreamSubscription(
                streamType: streamType,
                maxChunkLength: maxChunkSize,
                subscriber: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
    }
}

private enum StreamType {
    case data(Data)
    case url(URL)
}

private final class InputStreamSubscription<S: Subscriber>: Subscription
    where S.Input == [UInt8], S.Failure == Error
{
    private enum State {
        case streaming(InputStream)
        case error(Error)
        case finished
    }

    enum PublishResult {
        case doNotCallPublish
        case callPublish
        case finished
        case error(Error)
    }

    private enum InputStreamError: Error {
        case couldNotLoadFileAtURL(URL)
        case unknownError
    }

    private var state: State
    private let maxChunkLength: Int
    private var subscriber: S?
    private var demand = Subscribers.Demand.none
    private let lock = RecursiveLock()

    init(streamType: StreamType, maxChunkLength: Int, subscriber: S) {
        switch streamType {
        case let .data(data):
            let stream = InputStream(data: data)
            state = .streaming(stream)
            stream.open()
        case let .url(url):
            if let stream = InputStream(url: url) {
                state = .streaming(stream)
                stream.open()
            } else {
                state = .error(InputStreamError.couldNotLoadFileAtURL(url))
            }
        }
        self.maxChunkLength = maxChunkLength
        self.subscriber = subscriber
    }

    deinit {
        lock.locked {
            if case let .streaming(stream) = state {
                stream.close()
            }
        }
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand != .none else { return }
        let shouldPublish: Bool = lock.locked {
            let shouldPublish = self.demand == .none
            self.demand += demand
            return shouldPublish
        }
        guard shouldPublish else { return }
        publish()
    }

    func cancel() {
        lock.locked { subscriber = nil }
        complete(with: .finished)
    }

    private func publish() {
        let res: PublishResult = lock.locked {
            guard demand > .none else { return .doNotCallPublish }
            guard let sub = self.subscriber else { return .doNotCallPublish }

            switch state {
            case .finished, .error:
                // If our state is `.finished` or `.error`, it means
                // `complete(with:)` has already been called and the
                // subscriber has already been notified. So, we shouldn't
                // do anything here.
                return .doNotCallPublish
            case let .streaming(stream):
                var bytes = [UInt8](repeating: 0, count: maxChunkLength)
                let bytesRead = stream.read(&bytes, maxLength: maxChunkLength)

                demand -= .max(1)

                switch bytesRead {
                case -1:
                    stream.close()
                    return .error(stream.streamError ?? InputStreamError.unknownError)
                case 0:
                    stream.close()
                    return .finished
                default:
                    let newDemand = sub.receive(Array(bytes[0 ..< bytesRead]))
                    if newDemand != .none {
                        demand += newDemand
                    }
                    return .callPublish
                }
            }
        }

        switch res {
        case .doNotCallPublish:
            return
        case .callPublish:
            publish()
        case let .error(error):
            complete(with: .failure(error))
        case .finished:
            complete(with: .finished)
        }
    }

    private func complete(with completion: Subscribers.Completion<Error>) {
        lock.locked {
            if case let .streaming(stream) = state {
                stream.close()
            }

            switch completion {
            case .finished:
                state = .finished
            case let .failure(error):
                state = .error(error)
            }

            self.subscriber?.receive(completion: completion)
            self.subscriber = nil
        }
    }
}

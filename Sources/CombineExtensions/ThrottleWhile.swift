import Combine
import Foundation
import Synchronized

public extension Publisher {
    func throttle<Regulator: Publisher>(
        while regulator: Regulator,
        latest: Bool = true
    ) -> Publishers.ThrottleWhile<Self, Regulator>
        where Regulator.Output == Bool
    {
        Publishers.ThrottleWhile(
            upstream: self,
            regulator: regulator,
            latest: latest
        )
    }
}

public extension Publishers {
    struct ThrottleWhile<
        Upstream: Publisher,
        Regulator: Publisher
    >: Publisher
        where Regulator.Output == Bool, Upstream.Failure == Regulator.Failure
    {
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
            var state = State<Output>.waiting

            let regulatorSubject = CurrentValueSubject<
                Bool,
                Regulator.Failure
            >(false)

            var subscription: AnyCancellable? = regulator
                .subscribe(regulatorSubject)

            upstream
                .handleEvents(receiveCompletion: { completion in
                    state.receiveCompletion()
                    regulatorSubject.send(completion: completion)
                    subscription?.cancel()
                    subscription = nil
                })
                .combineLatest(regulatorSubject)
                .compactMap { (output: Output, shouldThrottle: Bool) -> Output? in
                    state.receiveValue(
                        output,
                        shouldThrottle: shouldThrottle,
                        latest: latest
                    )
                }
                .receive(subscriber: subscriber)
        }
    }
}

private enum State<Output> {
    case publishing
    case terminal
    case throttling(Output)
    case throttlingAndWaitingForOutput
    case waiting

    mutating func receiveCompletion() {
        self = .terminal
    }

    mutating func receiveValue(
        _ value: Output,
        shouldThrottle: Bool,
        latest: Bool
    ) -> Output? {
        switch self {
        case .publishing:
            if shouldThrottle {
                self = .throttlingAndWaitingForOutput
                return nil
            } else {
                return value
            }

        case .terminal:
            return nil

        case let .throttling(oldValue):
            if shouldThrottle {
                if latest {
                    self = .throttling(value)
                }
                return nil
            } else {
                self = .publishing
                if latest {
                    return value
                } else {
                    return oldValue
                }
            }

        case .throttlingAndWaitingForOutput:
            if shouldThrottle {
                self = .throttling(value)
                return nil
            } else {
                self = .publishing
                return nil
            }

        case .waiting:
            if shouldThrottle {
                self = .throttling(value)
                return nil
            } else {
                self = .publishing
                return value
            }
        }
    }
}

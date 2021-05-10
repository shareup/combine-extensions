import Foundation
import Combine
import Synchronized

extension Publisher {
    public func enumerated(startIndex: Int = 0) -> Publishers.Enumerated<Self> {
        Publishers.Enumerated(upstream: self, startIndex: startIndex)
    }
}

extension Publishers {
    public struct Enumerated<Upstream: Publisher>: Publisher {
        public typealias Output = (Int, Upstream.Output)
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream
        private let startIndex: Int

        public init(upstream: Upstream, startIndex: Int = 0) {
            self.upstream = upstream
            self.startIndex = startIndex
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Output == S.Input, Failure == S.Failure {
            let lock = Lock()
            var index = self.startIndex

            self.upstream
                .map { (value: Upstream.Output) -> (Int, Upstream.Output) in
                    let i: Int = lock.locked {
                        let i = index
                        index += 1
                        return i
                    }
                    return (i, value)
                }
                .receive(subscriber: subscriber)
        }
    }
}

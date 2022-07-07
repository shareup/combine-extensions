import Foundation
import Combine

extension Publisher {
    public func distinct<T: Hashable>() -> Publishers.Distinct<Self, T> where Output == Array<T> {
        Publishers.Distinct(upstream: self)
    }
}

extension Publishers {
    public struct Distinct<Upstream: Publisher, T: Hashable>: Publisher where Upstream.Output == Array<T> {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream

        public init(upstream: Upstream) {
            self.upstream = upstream
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Output == S.Input, Failure == S.Failure {
            var previousValues = Set<T>()

            self.upstream
                .compactMap { (values: Upstream.Output) -> Upstream.Output? in
                    var newValues: [T] = []
                    for value in values {
                        if !previousValues.contains(value) {
                            previousValues.insert(value)
                            newValues.append(value)
                        }
                    }
                    return newValues.isEmpty ? nil : newValues
                }
                .receive(subscriber: subscriber)
        }
    }
}



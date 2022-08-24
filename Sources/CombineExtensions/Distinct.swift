import Foundation
import Combine

extension Publisher {
    public func distinct<T: Hashable>() -> Publishers.Distinct<Self, T> where Output == Array<T> {
        Publishers.Distinct(upstream: self)
    }

    public func distinct<T, V: Hashable>(
        using transformer: @escaping (T) -> V
    ) -> Publishers.Distinct<Self, T> where Output == Array<T> {
        Publishers.Distinct(upstream: self, transformer: transformer)
    }
}

extension Publishers {
    public struct Distinct<Upstream: Publisher, T>: Publisher where Upstream.Output == Array<T> {

        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        private let upstream: Upstream
        private let isUnique: (T) -> Bool

        public init(upstream: Upstream) where T: Hashable {
            self.upstream = upstream

            var alreadySeen = Set<T>()
            isUnique = { output in
                guard !alreadySeen.contains(output) else { return false }
                alreadySeen.insert(output)
                return true
            }
        }

        public init<V: Hashable>(
            upstream: Upstream,
            transformer: @escaping (T) -> V
        ) {
            self.upstream = upstream

            var alreadySeen = Set<V>()
            isUnique = { output in
                let o = transformer(output)
                guard !alreadySeen.contains(o) else { return false }
                alreadySeen.insert(o)
                return true
            }
        }

        public func receive<S: Subscriber>(
            subscriber: S
        ) where Output == S.Input, Failure == S.Failure {
            self.upstream
                .compactMap { (values: Upstream.Output) -> Upstream.Output? in
                    let newValues = values.filter(isUnique)
                    return newValues.isEmpty ? nil : newValues
                }
                .receive(subscriber: subscriber)
        }
    }
}



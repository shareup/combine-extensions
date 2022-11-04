import Combine
import Foundation

public extension Publisher {
    func distinct<T: Hashable>() -> Publishers.Distinct<Self, T> where Output == [T] {
        Publishers.Distinct(upstream: self)
    }

    func distinct<T>(
        using transformer: @escaping (T) -> some Hashable
    ) -> Publishers.Distinct<Self, T> where Output == [T] {
        Publishers.Distinct(upstream: self, transformer: transformer)
    }
}

public extension Publishers {
    struct Distinct<Upstream: Publisher, T>: Publisher where Upstream.Output == [T] {
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
            upstream
                .compactMap { (values: Upstream.Output) -> Upstream.Output? in
                    let newValues = values.filter(isUnique)
                    return newValues.isEmpty ? nil : newValues
                }
                .receive(subscriber: subscriber)
        }
    }
}

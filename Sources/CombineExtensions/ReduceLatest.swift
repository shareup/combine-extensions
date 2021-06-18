import Combine
import Foundation
import Synchronized

public extension Publisher {
    func reduceLatest<B: Publisher, Output>(
        _ b: B,
        _ transform: @escaping (Self.Output?, B.Output?) -> Output
    ) -> Publishers.ReduceLatest<Self, B, Output> {
        Publishers.ReduceLatest(self, b, transform)
    }

    func reduceLatest<B: Publisher, C: Publisher, Output>(
        _ b: B,
        _ c: C,
        _ transform: @escaping (Self.Output?, B.Output?, C.Output?) -> Output
    ) -> Publishers.ReduceLatest3<Self, B, C, Output> {
        Publishers.ReduceLatest3(self, b, c, transform)
    }

    func reduceLatest<B: Publisher, C: Publisher, D: Publisher, Output>(
        _ b: B,
        _ c: C,
        _ d: D,
        _ transform: @escaping (Self.Output?, B.Output?, C.Output?, D.Output?) -> Output
    ) -> Publishers.ReduceLatest4<Self, B, C, D, Output> {
        Publishers.ReduceLatest4(self, b, c, d, transform)
    }
}

public extension Publishers {
    struct ReduceLatest<A: Publisher, B: Publisher, Output>: Publisher
        where A.Failure == B.Failure
    {
        public typealias Failure = A.Failure

        public let a: A
        public let b: B
        public let transform: (A.Output?, B.Output?) -> Output

        public init(_ a: A, _ b: B, _ transform: @escaping (A.Output?, B.Output?) -> Output) {
            self.a = a
            self.b = b
            self.transform = transform
        }

        public func receive<S: Subscriber>(subscriber: S)
            where S.Failure == Failure, S.Input == Output
        {
            let subscription = ReduceLatestSubscription(
                subscriber: subscriber,
                a: a,
                b: b,
                c: Just(()).setFailureType(to: Failure.self),
                d: Just(()).setFailureType(to: Failure.self),
                transform: { (aOut, bOut, _, _) -> Output in
                    self.transform(aOut, bOut)
                }
            )
            subscriber.receive(subscription: subscription)
        }
    }

    struct ReduceLatest3<A: Publisher, B: Publisher, C: Publisher, Output>: Publisher
        where A.Failure == B.Failure, A.Failure == C.Failure
    {
        public typealias Failure = A.Failure

        public let a: A
        public let b: B
        public let c: C
        public let transform: (A.Output?, B.Output?, C.Output?) -> Output

        public init(
            _ a: A,
            _ b: B,
            _ c: C,
            _ transform: @escaping (A.Output?, B.Output?, C.Output?) -> Output
        ) {
            self.a = a
            self.b = b
            self.c = c
            self.transform = transform
        }

        public func receive<S: Subscriber>(subscriber: S)
            where S.Failure == Failure, S.Input == Output
        {
            let subscription = ReduceLatestSubscription(
                subscriber: subscriber,
                a: a,
                b: b,
                c: c,
                d: Just(()).setFailureType(to: Failure.self),
                transform: { (aOut, bOut, cOut, _) -> Output in
                    self.transform(aOut, bOut, cOut)
                }
            )
            subscriber.receive(subscription: subscription)
        }
    }

    struct ReduceLatest4<A: Publisher, B: Publisher, C: Publisher, D: Publisher, Output>: Publisher
        where A.Failure == B.Failure, A.Failure == C.Failure, A.Failure == D.Failure
    {
        public typealias Failure = A.Failure

        public let a: A
        public let b: B
        public let c: C
        public let d: D
        public let transform: (A.Output?, B.Output?, C.Output?, D.Output?) -> Output

        public init(
            _ a: A,
            _ b: B,
            _ c: C,
            _ d: D,
            _ transform: @escaping (A.Output?, B.Output?, C.Output?, D.Output?) -> Output
        ) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.transform = transform
        }

        public func receive<S: Subscriber>(subscriber: S)
            where S.Failure == Failure, S.Input == Output
        {
            let subscription = ReduceLatestSubscription(
                subscriber: subscriber,
                a: a,
                b: b,
                c: c,
                d: d,
                transform: transform
            )
            subscriber.receive(subscription: subscription)
        }
    }
}

private final class ReduceLatestSubscription<Subscriber, A, B, C, D, Output, Failure>: Subscription
    where
    Subscriber: Combine.Subscriber,
    Subscriber.Input == Output,
    Subscriber.Failure == Failure,
    A: Publisher,
    B: Publisher,
    C: Publisher,
    D: Publisher,
    A.Failure == Failure,
    B.Failure == Failure,
    C.Failure == Failure,
    D.Failure == Failure
{
    private enum Key: String {
        case a, b, c, d
    }

    private let lock = RecursiveLock()
    private var tokens = [Key: AnyCancellable]()
    private var completions = [Key.a: false, .b: false, .c: false, .d: false]
    private var demand = Subscribers.Demand.none

    private var subscriber: Subscriber?
    private let transform: (A.Output?, B.Output?, C.Output?, D.Output?) -> Output

    private var latestA: A.Output?
    private var latestB: B.Output?
    private var latestC: C.Output?
    private var latestD: D.Output?

    init(
        subscriber: Subscriber,
        a: A,
        b: B,
        c: C,
        d: D,
        transform: @escaping (A.Output?, B.Output?, C.Output?, D.Output?) -> Output
    ) {
        self.subscriber = subscriber
        self.transform = transform

        let tokenA = a.sink(receiveCompletion: completeA, receiveValue: receiveA)
        let tokenB = b.sink(receiveCompletion: completeB, receiveValue: receiveB)
        let tokenC = c.sink(receiveCompletion: completeC, receiveValue: receiveC)
        let tokenD = d.sink(receiveCompletion: completeD, receiveValue: receiveD)

        [Key.a: tokenA, .b: tokenB, .c: tokenC, .d: tokenD]
            .forEach { tokens[$0] = $1 }
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
        lock.locked {
            guard demand > .none else { return }
            guard let sub = subscriber else { return }
            demand -= .max(1)
            let newDemand = sub.receive(transform(latestA, latestB, latestC, latestD))

            // Combine doesn’t treat `Subscribers.Demand.none` as zero and
            // adding or subtracting `.none` will trigger an exception.
            // https://www.raywenderlich.com/books/combine-asynchronous-programming-with-swift/v2.0/chapters/18-custom-publishers-handling-backpressure
            guard newDemand != .none else { return }

            demand += newDemand
        }
    }

    private func complete(with completion: Subscribers.Completion<Failure>) {
        lock.locked {
            let sub = self.subscriber
            self.subscriber = nil
            completions.removeAll()
            tokens.removeAll()
            sub?.receive(completion: completion)
        }
    }

    private func receiveA(_ input: A.Output) {
        lock.locked { latestA = input }
        publish()
    }

    private func receiveB(_ input: B.Output) {
        lock.locked { latestB = input }
        publish()
    }

    private func receiveC(_ input: C.Output) {
        lock.locked { latestC = input }
        publish()
    }

    private func receiveD(_ input: D.Output) {
        lock.locked { latestD = input }
        publish()
    }

    private func completeA(_ completion: Subscribers.Completion<A.Failure>) {
        completeUpstream(.a, completion)
    }

    private func completeB(_ completion: Subscribers.Completion<B.Failure>) {
        completeUpstream(.b, completion)
    }

    private func completeC(_ completion: Subscribers.Completion<C.Failure>) {
        completeUpstream(.c, completion)
    }

    private func completeD(_ completion: Subscribers.Completion<D.Failure>) {
        completeUpstream(.d, completion)
    }

    private func completeUpstream(
        _ key: Key,
        _ completion: Subscribers.Completion<Failure>
    ) {
        // Any upstream failure causes the `ReduceLatest` publisher to fail
        guard case .finished = completion else {
            complete(with: completion)
            return
        }

        let shouldComplete: Bool = lock.locked {
            tokens.removeValue(forKey: key)
            completions[key] = true
            return completions.reduce(true) { $0 && $1.value }
        }

        guard shouldComplete else { return }
        complete(with: completion)
    }
}

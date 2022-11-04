import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class ReduceLatestTests: XCTestCase {
    func testReduceLatestPublishesUntilLastUpstreamCompletes() throws {
        let pub1 = Just<Int>(1).setFailureType(to: Never.self)
        let pub2 = PassthroughSubject<Character, Never>()
        let pub3 = PassthroughSubject<Result3.State, Never>()

        let ex = pub1
            .reduceLatest(pub2, pub3, Result3.init)
            .expectOutput(
                [
                    Result3(1),
                    Result3(1, "A"),
                    Result3(1, "A", .ok),
                    Result3(1, "A", .great),
                ],
                completion: .finished
            )

        pub2.send("A")
        pub2.send(completion: .finished)
        pub2.send("B")
        pub3.send(.ok)
        pub3.send(.great)
        pub3.send(completion: .finished)
        pub3.send(.bad)

        wait(for: [ex], timeout: 2)
    }

    func testReduceLatestStopsPublishesAfterFirstFailure() throws {
        let pub1 = Just<Int>(1).setFailureType(to: ReducerError.self)
        let pub2 = PassthroughSubject<Character, ReducerError>()
        let pub3 = PassthroughSubject<Result3.State, ReducerError>()

        let ex = pub1
            .reduceLatest(pub2, pub3, Result3.init)
            .expectOutput(
                [
                    Result3(1),
                    Result3(1, "A"),
                    Result3(1, "A", .great),
                ],
                completion: .failure(.anError)
            )

        pub2.send("A")
        pub3.send(.great)
        pub2.send(completion: .failure(.anError))
        pub2.send("B")
        pub3.send(.bad)
        pub3.send(completion: .finished)
        pub3.send(.ok)

        wait(for: [ex], timeout: 2)
    }

    func testReduceLatest() throws {
        let pub1 = PassthroughSubject<Int, Never>()
        let pub2 = PassthroughSubject<Character, Never>()

        let ex = pub1
            .reduceLatest(pub2, Result.init)
            .expectOutput([
                Result(),
                Result(1),
                Result(2),
                Result(2, "A"),
            ])

        pub1.send(1)
        pub1.send(2)
        pub2.send("A")

        wait(for: [ex], timeout: 2)
    }

    func testReduceLatest3() throws {
        let pub1 = PassthroughSubject<Int, Never>()
        let pub2 = PassthroughSubject<Character, Never>()
        let pub3 = PassthroughSubject<Result3.State, Never>()

        let ex = pub1
            .reduceLatest(pub2, pub3, Result3.init)
            .expectOutput([
                Result3(),
                Result3(1),
                Result3(2),
                Result3(2, nil, .ok),
                Result3(2, "A", .ok),
                Result3(2, "B", .ok),
                Result3(2, "B", .great),
            ])

        pub1.send(1)
        pub1.send(2)
        pub3.send(.ok)
        pub2.send("A")
        pub2.send("B")
        pub3.send(.great)

        wait(for: [ex], timeout: 2)
    }

    func testReduceLatest4() throws {
        let pub1 = PassthroughSubject<Int, Never>()
        let pub2 = PassthroughSubject<Character, Never>()
        let pub3 = PassthroughSubject<Int, Never>()
        let pub4 = PassthroughSubject<Character, Never>()

        let ex = pub1
            .reduceLatest(pub2, pub3, pub4) { (Result($0, $1), Result($2, $3)) }
            .expectOutput(
                [
                    (Result(), Result()),
                    (Result(1), Result()),
                    (Result(2), Result()),
                    (Result(2, "A"), Result()),
                    (Result(2, "A"), Result(nil, "B")),
                    (Result(2, "A"), Result(nil, "C")),
                    (Result(2, "A"), Result(3, "C")),
                ],
                outputComparator:
                { (expected: (Result, Result), actual: (Result, Result)) -> Bool in
                    expected.0 == actual.0 && expected.1 == actual.1
                }
            )

        pub1.send(1)
        pub1.send(2)
        pub2.send("A")
        pub4.send("B")
        pub4.send("C")
        pub3.send(3)

        wait(for: [ex], timeout: 2)
    }
}

private enum ReducerError: Error, Equatable {
    case anError
}

private struct Result: CustomStringConvertible, Equatable {
    let number: Int?
    let letter: Character?

    init(_ number: Int? = nil, _ letter: Character? = nil) {
        self.number = number
        self.letter = letter
    }

    var description: String {
        "(\(String(describing: number)), \(String(describing: letter)))"
    }
}

private struct Result3: CustomStringConvertible, Equatable {
    fileprivate enum State: String {
        case bad, ok, great
    }

    let number: Int?
    let letter: Character?
    let state: State?

    init(_ number: Int? = nil, _ letter: Character? = nil, _ state: State? = nil) {
        self.number = number
        self.letter = letter
        self.state = state
    }

    var description: String {
        "(\(String(describing: number)), \(String(describing: letter)), \(String(describing: state)))"
    }
}

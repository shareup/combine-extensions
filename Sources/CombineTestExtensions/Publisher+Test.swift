import Foundation
import Combine
import XCTest

public extension Publisher where Output: Equatable {
    func expectOutput(
        _ expectedOutput: Output,
        failsOnCompletion: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        expectOutput(
            [expectedOutput],
            failsOnCompletion: failsOnCompletion,
            description: description,
            file: file,
            line: line
        )
    }

    func expectOutput(
        _ expectedOutput: [Output],
        failsOnCompletion: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            .values(expectedOutput),
            outputComparator: ==,
            completion: failsOnCompletion ? .none : .any,
            failureComparator: { _, _ in fatalError() },
            description: description,
            file: file,
            line: line
        )
    }

    func expectOutput(
        _ expectedOutput: [Output],
        expectToFinish: Bool,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            .values(expectedOutput),
            outputComparator: ==,
            completion: expectToFinish ? .finished : .any,
            failureComparator: { _, _ in fatalError() },
            description: description,
            file: file,
            line: line
        )
    }
}

public extension Publisher where Failure: Equatable {
    func expectFailure(
        _ expectedFailure: Failure,
        failsOnOutput: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    )  -> XCTestExpectation {
        _expectOutput(
            failsOnOutput ? .none : .any,
            outputComparator: { _, _ in fatalError() },
            completion: .failure(expectedFailure),
            failureComparator: { $0 == $1 },
            description: description,
            file: file,
            line: line
        )
    }
}

public extension Publisher where Output: Equatable, Failure: Equatable {
    func expectOutput(
        _ expectedOutput: [Output],
        completion expectedCompletion: Subscribers.Completion<Failure>,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            .values(expectedOutput),
            outputComparator: ==,
            completion: _Completion(expectedCompletion),
            failureComparator: ==,
            description: description,
            file: file,
            line: line
        )
    }
}

public extension Publisher {
    func expectOutput(
        count: Int,
        failsOnCompletion: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        let description = description ?? "Should have received values \(count) times"
        let ex = _Expectation(description: description)
        ex.expectedFulfillmentCount = count
        let token = sink(
            receiveCompletion: { (completion) in
                if failsOnCompletion {
                    XCTFail(
                        "Should not have completed: '\(String(describing: completion))'",
                        file: file,
                        line: line
                    )
                }
            },
            receiveValue: { _ in ex.fulfill() }
        )
        ex.token = token
        return ex
    }

    func expectOutput(
        _ expectedOutput: [Output],
        outputComparator: @escaping (Output, Output) -> Bool,
        failsOnCompletion: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            .values(expectedOutput),
            outputComparator: outputComparator,
            completion: failsOnCompletion ? .none : .any,
            failureComparator: { _, _ in fatalError() },
            description: description,
            file: file,
            line: line
        )
    }

    func expectOutput(
        _ expectedOutput: [Output],
        outputComparator: @escaping (Output, Output) -> Bool,
        completion expectedCompletion: Subscribers.Completion<Failure>,
        failureComparator: @escaping (Failure, Failure) -> Bool,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            .values(expectedOutput),
            outputComparator: outputComparator,
            completion: _Completion(expectedCompletion),
            failureComparator: failureComparator,
            description: description,
            file: file,
            line: line
        )
    }

    func expectToFinish(
        failsOnOutput: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        _expectOutput(
            failsOnOutput ? .none : .any,
            outputComparator: { _, _ in fatalError() },
            completion: .finished,
            failureComparator: { _, _ in fatalError() },
            description: description,
            file: file,
            line: line
        )
    }

    func expectAnyFailure(
        failsOnOutput: Bool = false,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    )  -> XCTestExpectation {
        _expectOutput(
            failsOnOutput ? .none : .any,
            outputComparator: { _, _ in fatalError() },
            completion: .anyFailure,
            failureComparator: { _, _ in fatalError() },
            description: description,
            file: file,
            line: line
        )
    }
}

private extension Publisher {
    func _expectOutput(
        _ expectedOutput: _Output<Output>,
        outputComparator: @escaping (Output, Output) -> Bool,
        completion expectedCompletion: _Completion<Failure>,
        failureComparator: @escaping (Failure, Failure) -> Bool,
        description: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCTestExpectation {
        let description = description ?? "Output should have equalled '\(expectedOutput)'"
        var expectedOutput = expectedOutput

        let ex = _Expectation(description: description)
        ex.assertForOverFulfill = true
        if expectedOutput.shouldWaitForOutput && expectedCompletion.shouldWaitForCompletion {
            ex.expectedFulfillmentCount = 2
        }

        let token = sink(
            receiveCompletion: { (completion) in
                switch (expectedCompletion, completion) {
                case (.any, _):
                    break

                case (.none, _):
                    XCTFail(
                        "Should not have completed: '\(String(describing: completion))'",
                        file: file,
                        line: line
                    )

                case (.finished, .finished):
                    ex.fulfill()

                case let (.failure(expectedError), .failure(receivedError)):
                    XCTAssertTrue(
                        failureComparator(expectedError, receivedError),
                        file: file,
                        line: line
                    )
                    ex.fulfill()

                case (.anyFailure, .failure):
                    ex.fulfill()

                case let (.finished, .failure(receivedError)):
                    XCTFail(
                        "Should not have received failure: \(String(describing: receivedError))",
                        file: file,
                        line: line
                    )
                    ex.fulfill()

                case let (.failure(expectedError), .finished):
                    XCTFail(
                        "Should have received failure: \(String(describing: expectedError))",
                        file: file,
                        line: line
                    )
                    ex.fulfill()

                case (.anyFailure, .finished):
                    XCTFail(
                        "Should have received failure",
                        file: file,
                        line: line
                    )
                    ex.fulfill()
                }
            },
            receiveValue: { (output) in
                switch expectedOutput {
                case .any:
                    break
                case .none:
                    XCTFail("Should not have received any output", file: file, line: line)
                case var .values(expectedValues):
                    guard !expectedValues.isEmpty else {
                        if ex.assertForOverFulfill {
                            XCTFail(
                                "Received unexpected output: '\(String(describing: output))'",
                                file: file,
                                line: line
                            )
                        }
                        return
                    }
                    
                    let expected = expectedValues.removeFirst()
                    XCTAssertTrue(
                        outputComparator(expected, output),
                        file: file,
                        line: line)

                    expectedOutput = .values(expectedValues)
                    if expectedValues.isEmpty {
                        ex.fulfill()
                    }
                }
            }
        )
        ex.token = token
        return ex
    }
}

private enum _Output<T>: CustomStringConvertible {
    case any
    case none
    case values([T])

    var description: String {
        switch self {
        case .any:
            return "<anything>"
        case .none:
            return "<nothing>"
        case let .values(values):
            return String(describing: values)
        }
    }

    var shouldWaitForOutput: Bool {
        switch self {
        case .any, .none:
            return false
        case .values:
            return true
        }
    }
}

extension _Output: Equatable where T: Equatable {}

private enum _Completion<Failure: Error> {
    case any
    case none
    case finished
    case failure(Failure)
    case anyFailure

    init(_ completion: Subscribers.Completion<Failure>) {
        switch completion {
        case .finished:
            self = .finished
        case let .failure(error):
            self = .failure(error)
        }
    }

    var shouldWaitForCompletion: Bool {
        switch self {
        case .any, .none:
            return false
        case .finished, .failure, .anyFailure:
            return true
        }
    }
}

extension _Completion: Equatable where Failure: Equatable {}

private class _Expectation: XCTestExpectation {
    var token: AnyCancellable?

    private var fulfillmentCount: Int = 0

    override func fulfill() {
        super.fulfill()

        fulfillmentCount += 1
        if fulfillmentCount == expectedFulfillmentCount {
            token?.cancel()
            token = nil
        }
    }
}

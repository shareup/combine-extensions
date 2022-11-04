import Combine
import CombineTestExtensions
import XCTest

class PublisherTestExtensionsTests: XCTestCase {
    func testExpectOutputWithEvaluator() throws {
        var ints = [1, 2, 3]
        let evaluator = { (input: Int) -> OutputExpectation in
            XCTAssertEqual(ints.removeFirst(), input)
            return ints.isEmpty ? .finished : .moreExpected
        }
        let ex = ints.publisher.expectOutput(evaluator, expectToFinish: true)

        wait(for: [ex], timeout: 0.5)
    }

    func testExpectOutputAndFailureWithEvaluators() throws {
        let subject = PassthroughSubject<Int, Err>()

        var ints = [1, 2, 3]

        let ex = subject
            .receive(on: DispatchQueue(label: "test"))
            .expectOutputAndFailure(
                { output -> OutputExpectation in
                    XCTAssertEqual(ints.removeFirst(), output)
                    return ints.isEmpty ? .finished : .moreExpected
                },
                failureEvaluator: { XCTAssertEqual(.correct, $0) }
            )

        subject.send(1)
        subject.send(2)
        subject.send(3)
        subject.send(completion: .failure(.correct))

        wait(for: [ex], timeout: 0.5)
    }

    func testExpectFailureWithEvaluator() throws {
        let subject = PassthroughSubject<Int, Err>()

        let ex = subject
            .receive(on: DispatchQueue(label: "test"))
            .expectFailure(
                { XCTAssertEqual(.correct, $0) },
                failsOnOutput: true
            )

        subject.send(completion: .failure(.correct))

        wait(for: [ex], timeout: 0.5)
    }
}

private enum Err: Error, Equatable {
    case correct
    case wrong
}

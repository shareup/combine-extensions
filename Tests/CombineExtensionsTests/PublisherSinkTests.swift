import Combine
import CombineExtensions
import XCTest

final class PublisherSinkTests: XCTestCase {
    func testSinkReceiveValueReceiveCompletionOverloadReceivesValuesThenCompletion() throws {
        let subject = PassthroughSubject<Int, SinkError>()

        var values = [Int]()
        var completion: Subscribers.Completion<SinkError>?

        let subscription = subject.sink(
            receiveValue: { values.append($0) },
            receiveCompletion: { completion = $0 }
        )

        subject.send(1)
        subject.send(2)
        subject.send(completion: .failure(.failed))
        subject.send(3)

        XCTAssertEqual([1, 2], values)
        XCTAssertEqual(.failure(.failed), completion)

        subscription.cancel()
    }

    func testVoidSinkCompletionOverloadIgnoresValuesAndReceivesCompletion() throws {
        let subject = PassthroughSubject<Void, SinkError>()

        var completion: Subscribers.Completion<SinkError>?

        let subscription = subject.sink { completion = $0 }

        subject.send(())
        subject.send(())
        subject.send(completion: .finished)

        XCTAssertEqual(.finished, completion)

        subscription.cancel()
    }
}

private enum SinkError: Error, Equatable {
    case failed
}

import Combine
import CombineExtensions
import XCTest

class OnCancelTests: XCTestCase {
    func testOnCancelIsCalledWhenCancelled() throws {
        let subject = PassthroughSubject<Int, _Err>()

        var receivedValues = [Int]()
        var receivedCompletion: Subscribers.Completion<_Err>?
        var onCancelCalled = false

        let cancellable = subject.sink(
            receiveValue: { receivedValues.append($0) },
            receiveCompletion: { receivedCompletion = $0 }
        )
        .onCancel { onCancelCalled = true }

        subject.send(1)
        subject.send(2)
        cancellable.cancel()
        subject.send(3)
        subject.send(completion: .finished)

        XCTAssertEqual([1, 2], receivedValues)
        XCTAssertNil(receivedCompletion)
        XCTAssertTrue(onCancelCalled)
    }

    func testOnCancelIsCalledAfterSubjectIsCompleted() throws {
        let subject = PassthroughSubject<Int, _Err>()

        var receivedValues = [Int]()
        var receivedCompletion: Subscribers.Completion<_Err>?
        var onCancelCalled = false

        let cancellable = subject.sink(
            receiveValue: { receivedValues.append($0) },
            receiveCompletion: { receivedCompletion = $0 }
        )
        .onCancel { onCancelCalled = true }

        subject.send(1)
        subject.send(2)
        subject.send(completion: .failure(_Err()))
        subject.send(3)
        cancellable.cancel()

        XCTAssertEqual([1, 2], receivedValues)
        XCTAssertEqual(.failure(_Err()), receivedCompletion)
        XCTAssertTrue(onCancelCalled)
    }
}

private struct _Err: Error, Equatable {}

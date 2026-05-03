import Combine
import CombineExtensions
import XCTest

class OnCancelTests: XCTestCase {
    func testOnCancelCancelsWrappedCancellableBeforeRunningBlock() throws {
        var events = [String]()
        let wrapped = SpyCancellable { events.append("cancel") }

        let cancellable = wrapped.onCancel {
            XCTAssertTrue(wrapped.isCancelled)
            events.append("block")
        }

        cancellable.cancel()

        XCTAssertEqual(["cancel", "block"], events)
    }

    func testOnCancelBlockRunsOnlyOnceWhenCancelledMultipleTimes() throws {
        var cancelCount = 0
        var blockCount = 0

        let wrapped = SpyCancellable { cancelCount += 1 }
        let cancellable = wrapped.onCancel { blockCount += 1 }

        cancellable.cancel()
        cancellable.cancel()

        XCTAssertEqual(1, cancelCount)
        XCTAssertEqual(1, blockCount)
    }

    func testOnCancelRunsWhenReturnedCancellableIsDeallocated() throws {
        var cancelCount = 0
        var blockCount = 0

        let wrapped = SpyCancellable { cancelCount += 1 }
        var cancellable: AnyCancellable? = wrapped.onCancel { blockCount += 1 }

        XCTAssertNotNil(cancellable)
        cancellable = nil

        XCTAssertEqual(1, cancelCount)
        XCTAssertEqual(1, blockCount)
    }

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

private final class SpyCancellable: Cancellable {
    private let onCancel: () -> Void
    private(set) var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        isCancelled = true
        onCancel()
    }
}

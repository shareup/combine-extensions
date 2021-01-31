import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class BufferPassthroughSubjectTests: XCTestCase {
    func testBuffersValuesUntilReceivingSubscriber() throws {
        let subject = BufferPassthroughSubject<Int, Never>()
        subject.send(0)
        subject.send(1)
        subject.send(2)

        let ex = subject.expectOutput([0, 1, 2])
        wait(for: [ex], timeout: 2)
    }

    func testBuffersValuesAndCompletionUntilReceivingSubscriber() throws {
        let subject = BufferPassthroughSubject<Int, Never>()
        subject.send(0)
        subject.send(1)
        subject.send(2)
        subject.send(completion: .finished)

        let ex = subject.expectOutput([0, 1, 2], completion: .finished)
        wait(for: [ex], timeout: 2)
    }

    func testPassesThroughValuesAfterReceivingSubscriber() throws {
        let subject = BufferPassthroughSubject<Int, Never>()

        subject.send(0)

        let bufferEx = subject.expectOutput([0])
        bufferEx.assertForOverFulfill = false
        wait(for: [bufferEx], timeout: 2)

        let newEx = subject.expectOutput([1, 2])

        subject.send(1)
        subject.send(2)

        wait(for: [newEx], timeout: 2)
    }

    func testOnlyFirstSubscriberReceivesBufferedValues() throws {
        let subject = BufferPassthroughSubject<Int, Never>()

        subject.send(0)

        let bufferEx = subject.expectOutput([0, 1], completion: .finished)
        let passthroughEx = subject.expectOutput([1], completion: .finished)

        subject.send(1)
        subject.send(completion: .finished)

        wait(for: [bufferEx, passthroughEx], timeout: 2)
    }

    func testPassesThroughOnlyBufferedValuesReceivedBeforeCompletion() throws {
        let subject = BufferPassthroughSubject<Int, TestError>()

        subject.send(0)

        let bufferEx = subject.expectOutput([0, 1], completion: .failure(.error))
        let passthroughEx = subject.expectOutput([1], completion: .failure(.error))

        subject.send(1)
        subject.send(completion: .failure(.error))

        let noOutputEx = subject.expectOutput([2])
        noOutputEx.isInverted = true

        subject.send(2)

        wait(for: [bufferEx, passthroughEx, noOutputEx], timeout: 0.1)
    }
}

private enum TestError: Error, Equatable {
    case error
}

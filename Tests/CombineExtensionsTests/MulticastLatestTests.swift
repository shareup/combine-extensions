import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class MulticastLatestSubjectTests: XCTestCase {
    func testMulticastLatestDoesNotEmitUntilUpstreamPublishes() {
        let subject = PassthroughSubject<Int, Never>()

        var values = [Int]()
        let subscription = subject
            .multicastLatest()
            .sink { values.append($0) }

        XCTAssertEqual([], values)

        subject.send(1)

        XCTAssertEqual([1], values)

        subscription.cancel()
    }

    func testLateSubscriberReceivesLatestValueImmediately() {
        let subject = PassthroughSubject<Int, Never>()
        let publisher = subject.multicastLatest()

        var firstValues = [Int]()
        let firstSubscription = publisher.sink { firstValues.append($0) }

        subject.send(1)
        subject.send(2)

        var secondValues = [Int]()
        let secondSubscription = publisher.sink { secondValues.append($0) }

        XCTAssertEqual([1, 2], firstValues)
        XCTAssertEqual([2], secondValues)

        firstSubscription.cancel()
        secondSubscription.cancel()
    }

    func testMulticastLatestForwardsFinishedCompletion() {
        let subject = PassthroughSubject<Int, Never>()

        var values = [Int]()
        var completion: Subscribers.Completion<Never>?
        let subscription = subject
            .multicastLatest()
            .sink(
                receiveCompletion: { completion = $0 },
                receiveValue: { values.append($0) }
            )

        subject.send(1)
        subject.send(completion: .finished)
        subject.send(2)

        XCTAssertEqual([1], values)
        XCTAssertEqual(.finished, completion)

        subscription.cancel()
    }

    func testMulticastLatestForwardsFailure() {
        let subject = PassthroughSubject<Int, MulticastError>()

        var values = [Int]()
        var completion: Subscribers.Completion<MulticastError>?
        let subscription = subject
            .multicastLatest()
            .sink(
                receiveCompletion: { completion = $0 },
                receiveValue: { values.append($0) }
            )

        subject.send(1)
        subject.send(completion: .failure(.failed))
        subject.send(2)

        XCTAssertEqual([1], values)
        XCTAssertEqual(.failure(.failed), completion)

        subscription.cancel()
    }

    func testMulticastLatest() {
        let voidSubject = PassthroughSubject<Void, Never>()
        let intSubject = PassthroughSubject<Int, Never>()
        var mapCalledCount = 0

        let multicastedPublisher = voidSubject
            .map {
                mapCalledCount += 1
                return intSubject
            }
            .switchToLatest()
            .multicastLatest()

        let outputExpectation = multicastedPublisher.expectOutput([1, 2])

        voidSubject.send(())
        intSubject.send(1)
        intSubject.send(2)

        let expectation1 = expectation(description: "first subscriber")
        let subscription1 = multicastedPublisher.sink { value in
            XCTAssertEqual(value, 2)
            expectation1.fulfill()
        }
        defer { subscription1.cancel() }

        let expectation2 = expectation(description: "second subscriber")
        let subscription2 = multicastedPublisher.sink { value in
            XCTAssertEqual(value, 2)
            expectation2.fulfill()
        }
        defer { subscription2.cancel() }

        wait(for: [outputExpectation, expectation1, expectation2], timeout: 0.5)
        XCTAssertEqual(mapCalledCount, 1)
    }
}

private enum MulticastError: Error, Equatable {
    case failed
}

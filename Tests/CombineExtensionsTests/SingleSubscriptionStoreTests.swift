import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class SingleSubscriptionStoreTests: XCTestCase {
    func testSingleSubscriptionStoreIsEmptyAndContains() throws {
        let store = SingleSubscriptionStore()

        XCTAssertTrue(store.isEmpty)

        [1, 2, 3].publisher.sink { _ in }.store(in: store)

        XCTAssertFalse(store.isEmpty)

        store.removeSubscription()
        XCTAssertTrue(store.isEmpty)
    }

    func testSingleSubscriptionStoreEquatableAndHashable() throws {
        let one = SingleSubscriptionStore()
        let two = SingleSubscriptionStore()

        let sameAsOne = one

        XCTAssertEqual(one, one)
        XCTAssertEqual(one, sameAsOne)
        XCTAssertEqual(one.hashValue, one.hashValue)
        XCTAssertEqual(one.hashValue, sameAsOne.hashValue)

        XCTAssertNotEqual(one, two)
        XCTAssertNotEqual(one.hashValue, two.hashValue)

        [1, 2, 3]
            .publisher
            .sink { _ in }
            .store(in: sameAsOne)

        XCTAssertEqual(one, sameAsOne)
        XCTAssertEqual(one.hashValue, sameAsOne.hashValue)
    }

    func testStoringSubscriptionPreventsCancellation() throws {
        let store = SingleSubscriptionStore()

        let subject = PassthroughSubject<Int, Never>()

        let receiveEx = expectation(description: "Should have received '1'")
        receiveEx.assertForOverFulfill = true

        let doNotReceiveEx = expectation(description: "Should not have received '2'")
        doNotReceiveEx.isInverted = true

        subject.sink { value in
            if value == 1 {
                receiveEx.fulfill()
            } else if value == 2 {
                doNotReceiveEx.fulfill()
            } else {
                XCTFail()
            }
        }
        .store(in: store)

        subject.send(1)
        wait(for: [receiveEx], timeout: 2)

        store.removeSubscription()
        subject.send(2)
        wait(for: [doNotReceiveEx], timeout: 0.1)
    }
}

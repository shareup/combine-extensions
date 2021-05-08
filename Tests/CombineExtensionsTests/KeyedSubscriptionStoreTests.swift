import XCTest
import Combine
import CombineExtensions
import CombineTestExtensions

class KeyedSubscriptionStoreTests: XCTestCase {
    func testKeyedSubscriptionStoreEquatableAndHashable() throws {
        let one = KeyedSubscriptionStore()
        let two = KeyedSubscriptionStore()

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
            .store(in: sameAsOne, key: "integers")

        XCTAssertEqual(one, sameAsOne)
        XCTAssertEqual(one.hashValue, sameAsOne.hashValue)
    }

    func testStoringSubscriptionPreventsCancellation() throws {
        let store = KeyedSubscriptionStore()

        let subject1 = PassthroughSubject<Int, Never>()
        let subject2 = PassthroughSubject<Int, Never>()

        let subject1Ex = expectation(description: "Should have received '1' and '3'")
        subject1Ex.expectedFulfillmentCount = 2
        let subject2Ex = expectation(description: "Should have received '2'")
        let doNotReceiveEx = expectation(description: "Should not have received '4'")
        doNotReceiveEx.isInverted = true

        subject1.sink { value in
            if value == 1 || value == 3 { subject1Ex.fulfill() }
            else { XCTFail() }
        }
        .store(in: store, key: "subject1")

        subject2.sink { value in
            if value == 2 { subject2Ex.fulfill() }
            else { doNotReceiveEx.fulfill() }
        }
        .store(in: store, key: "subject2")

        subject1.send(1)
        subject2.send(2)
        store.removeSubscription(forKey: "subject2")
        subject1.send(3)
        subject2.send(4)

        wait(for: [subject1Ex, subject2Ex], timeout: 2)
        wait(for: [doNotReceiveEx], timeout: 0.1)
    }
}


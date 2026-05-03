import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class KeyedSubscriptionStoreTests: XCTestCase {
    func testKeyedSubscriptionStoreIsEmptyAndContains() throws {
        let store = KeyedSubscriptionStore()

        XCTAssertTrue(store.isEmpty)

        [1, 2, 3].publisher.sink { _ in }.store(in: store, key: "first")
        [1, 2, 3].publisher.sink { _ in }.store(in: store, key: "second")

        XCTAssertFalse(store.isEmpty)
        XCTAssertTrue(store.containsSubscription(forKey: "first"))
        XCTAssertTrue(store.containsSubscription(forKey: "second"))
        XCTAssertFalse(store.containsSubscription(forKey: "third"))

        store.removeSubscription(forKey: "second")
        XCTAssertFalse(store.isEmpty)
        XCTAssertTrue(store.containsSubscription(forKey: "first"))
        XCTAssertFalse(store.containsSubscription(forKey: "second"))
        XCTAssertFalse(store.containsSubscription(forKey: "third"))

        store.removeSubscription(forKey: "first")
        XCTAssertTrue(store.isEmpty)
        XCTAssertFalse(store.containsSubscription(forKey: "first"))
        XCTAssertFalse(store.containsSubscription(forKey: "second"))
        XCTAssertFalse(store.containsSubscription(forKey: "third"))
    }

    func testKeyedSubscriptionStoreInitializerStoresSubscriptions() throws {
        var cancelCount = 0

        let store = KeyedSubscriptionStore(
            subscriptions: ["initial": AnyCancellable { cancelCount += 1 }]
        )

        XCTAssertFalse(store.isEmpty)
        XCTAssertTrue(store.containsSubscription(forKey: "initial"))

        store.removeAll()

        XCTAssertEqual(1, cancelCount)
    }

    func testStoringSubscriptionForExistingKeyCancelsPreviousSubscription() throws {
        let store = KeyedSubscriptionStore()

        var firstCancelCount = 0
        var secondCancelCount = 0

        store.store(
            subscription: AnyCancellable { firstCancelCount += 1 },
            forKey: "shared"
        )

        store.store(
            subscription: AnyCancellable { secondCancelCount += 1 },
            forKey: "shared"
        )

        XCTAssertEqual(1, firstCancelCount)
        XCTAssertEqual(0, secondCancelCount)

        store.removeAll()

        XCTAssertEqual(1, firstCancelCount)
        XCTAssertEqual(1, secondCancelCount)
    }

    func testRemovedSubscriptionStaysActiveWhileReturnedValueIsRetained() throws {
        let store = KeyedSubscriptionStore()
        let subject = PassthroughSubject<Int, Never>()

        var receivedValues = [Int]()
        subject
            .sink { receivedValues.append($0) }
            .store(in: store, key: "subject")

        var removedSubscription = store.removeSubscription(forKey: "subject")

        XCTAssertNotNil(removedSubscription)
        XCTAssertTrue(store.isEmpty)

        subject.send(1)

        XCTAssertEqual([1], receivedValues)

        removedSubscription = nil
        subject.send(2)

        XCTAssertEqual([1], receivedValues)
    }

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

    func testRemoveAll() throws {
        let store = KeyedSubscriptionStore()

        let subject1 = PassthroughSubject<Int, Never>()
        let subject2 = PassthroughSubject<Int, Never>()

        var receivedFrom1 = [Int]()
        var receivedFrom2 = [Int]()

        subject1
            .sink(receiveValue: { receivedFrom1.append($0) })
            .store(in: store, key: "one")

        subject2
            .sink(receiveValue: { receivedFrom2.append($0) })
            .store(in: store, key: "two")

        subject1.send(1)
        subject2.send(2)
        store.removeAll()
        subject1.send(11)
        subject2.send(12)

        XCTAssertEqual([1], receivedFrom1)
        XCTAssertEqual([2], receivedFrom2)
    }
}

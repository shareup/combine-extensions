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

    func testSingleSubscriptionStoreInitializerStoresSubscription() throws {
        var cancelCount = 0
        let store = SingleSubscriptionStore(AnyCancellable { cancelCount += 1 })

        XCTAssertFalse(store.isEmpty)

        store.removeSubscription()

        XCTAssertEqual(1, cancelCount)
        XCTAssertTrue(store.isEmpty)
    }

    func testStoringNewSubscriptionCancelsPreviousSubscription() throws {
        let store = SingleSubscriptionStore()

        var firstCancelCount = 0
        var secondCancelCount = 0

        store.store(subscription: AnyCancellable { firstCancelCount += 1 })
        store.store(subscription: AnyCancellable { secondCancelCount += 1 })

        XCTAssertEqual(1, firstCancelCount)
        XCTAssertEqual(0, secondCancelCount)

        store.removeSubscription()

        XCTAssertEqual(1, firstCancelCount)
        XCTAssertEqual(1, secondCancelCount)
    }

    func testRemovedSubscriptionStaysActiveWhileReturnedValueIsRetained() throws {
        let store = SingleSubscriptionStore()
        let subject = PassthroughSubject<Int, Never>()

        var receivedValues = [Int]()
        subject
            .sink { receivedValues.append($0) }
            .store(in: store)

        var removedSubscription = store.removeSubscription()

        XCTAssertNotNil(removedSubscription)
        XCTAssertTrue(store.isEmpty)

        subject.send(1)

        XCTAssertEqual([1], receivedValues)

        removedSubscription = nil
        subject.send(2)

        XCTAssertEqual([1], receivedValues)
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

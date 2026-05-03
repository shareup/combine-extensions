import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

final class AnyConnectablePublisherTests: XCTestCase {
    func testErasedPublisherForwardsSubscribersAndConnects() throws {
        let wrapped = TrackingConnectablePublisher()
        let publisher = wrapped.eraseToAnyConnectablePublisher()

        var values = [Int]()
        let subscription = publisher.sink { values.append($0) }

        XCTAssertEqual(1, wrapped.subscriberCount)

        wrapped.subject.send(1)
        XCTAssertEqual([1], values)

        let connection = publisher.connect()
        XCTAssertEqual(1, wrapped.connectCount)

        connection.cancel()
        XCTAssertEqual(1, wrapped.connectionCancelCount)

        subscription.cancel()
    }

    func testAutoconnectConnectsAndCancelsErasedPublisher() throws {
        let wrapped = TrackingConnectablePublisher()
        let publisher = wrapped.eraseToAnyConnectablePublisher()

        let subscription = publisher
            .autoconnect()
            .sink { (_: Int) in }

        XCTAssertEqual(1, wrapped.subscriberCount)
        XCTAssertEqual(1, wrapped.connectCount)
        XCTAssertEqual(0, wrapped.connectionCancelCount)

        subscription.cancel()

        XCTAssertEqual(1, wrapped.connectionCancelCount)
    }

    func testErasedTimerCanStillBeConnectedTo() throws {
        let pub = Timer.publish(every: 0.01, on: .main, in: .common)
            .eraseToAnyConnectablePublisher()

        var dates = [Date]()
        var subscriptions = Set<AnyCancellable>()
        pub.sink { date in
            dates.append(date)
            subscriptions.removeAll()
        }
        .store(in: &subscriptions)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(dates.isEmpty)

        pub.connect().store(in: &subscriptions)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(1, dates.count)
        XCTAssertTrue(subscriptions.isEmpty)
    }

    func testAutoconnectAnyConnectablePublisher() throws {
        var dates = [Date]()
        var subscriptions = Set<AnyCancellable>()

        Timer
            .publish(every: 0.01, on: .main, in: .common)
            .eraseToAnyConnectablePublisher()
            .autoconnect()
            .sink { date in
                dates.append(date)
                subscriptions.removeAll()
            }
            .store(in: &subscriptions)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(1, dates.count)
        XCTAssertTrue(subscriptions.isEmpty)
    }
}

private final class TrackingConnectablePublisher: ConnectablePublisher {
    typealias Output = Int
    typealias Failure = Never

    let subject = PassthroughSubject<Int, Never>()
    private(set) var subscriberCount = 0
    private(set) var connectCount = 0
    private(set) var connectionCancelCount = 0

    func receive<S: Subscriber>(
        subscriber: S
    ) where S.Input == Int, S.Failure == Never {
        subscriberCount += 1
        subject.receive(subscriber: subscriber)
    }

    func connect() -> Cancellable {
        connectCount += 1

        return AnyCancellable { [weak self] in
            self?.connectionCancelCount += 1
        }
    }
}

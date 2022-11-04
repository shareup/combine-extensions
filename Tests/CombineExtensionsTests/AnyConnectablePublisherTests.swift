import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

final class AnyConnectablePublisherTests: XCTestCase {
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

import Combine
import CombineExtensions
import XCTest

final class AgainAtTests: XCTestCase {
    func testPublisherExtensionPublishesUpstreamOutputAndTimer() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var timerNows = [DispatchQueue.SchedulerTimeType]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    timerNows.append(timer.now)
                }
            )
        defer { subscription.cancel() }

        subject.send(1)

        XCTAssertTrue(values.isEmpty)

        scheduler.advance()

        XCTAssertEqual(values, [1])
        XCTAssertEqual(timerNows, [scheduler.now])
    }

    func testPublishersAgainAtInitializerPublishesUpstreamOutputAndTimer() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var timerNows = [DispatchQueue.SchedulerTimeType]()

        let subscription = Publishers.AgainAt(
            upstream: subject,
            scheduler: scheduler,
            options: nil
        )
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { value, timer in
                values.append(value)
                timerNows.append(timer.now)
            }
        )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        XCTAssertEqual(values, [1])
        XCTAssertEqual(timerNows, [scheduler.now])
    }

    func testRepublishPublishesAfterRequestedTime() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))

        scheduler.advance(by: .milliseconds(999))
        XCTAssertEqual(values, [1])

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(values, [1, 1])
    }

    func testRepublishAtCurrentSchedulerTimeFiresOnNextAdvance() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now)

        XCTAssertEqual(values, [1])

        scheduler.advance()

        XCTAssertEqual(values, [1, 1])
    }

    func testRepublishAtFutureDatePublishesAfterConvertedTime() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [DateRepublisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: timer.time(at: $0)) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](Date(timeIntervalSinceNow: 1))

        scheduler.advance(by: .milliseconds(500))
        XCTAssertEqual(values, [1])

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 1])
    }

    func testRepublishAtPastDateUsesCurrentSchedulerTime() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [DateRepublisher]()
        var timerNows = [DispatchQueue.SchedulerTimeType]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    timerNows.append(timer.now)
                    republishers.append { timer.republish(at: timer.time(at: $0)) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        let firstNow = scheduler.now
        scheduler.advance(by: .seconds(5))
        let republishNow = scheduler.now

        republishers[0](.distantPast)
        scheduler.advance()

        XCTAssertEqual(values, [1, 1])
        XCTAssertEqual(timerNows, [firstNow, republishNow])
    }

    func testTimeAtDistantFutureDoesNotOverflow() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var convertedTimes = [DispatchQueue.SchedulerTimeType]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _, timer in
                    convertedTimes.append(timer.time(at: .distantFuture))
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        XCTAssertEqual(convertedTimes.count, 1)
        XCTAssertTrue(convertedTimes[0] > scheduler.now)
    }

    func testRepublishPublishesNewestUpstreamOutputAtFireTime() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))

        subject.send(2)
        scheduler.advance()

        XCTAssertEqual(values, [1, 2])

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 2, 2])
    }

    func testOnlyMostRecentlySetRepublishTimeFires() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        republishers[0](scheduler.now.advanced(by: .seconds(2)))

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1])

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 1])
    }

    func testMultipleRepublishersAtSameDateOnlyFireOnce() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        let fireDate = scheduler.now.advanced(by: .seconds(1))
        republishers[0](fireDate)
        republishers[0](fireDate)
        republishers[0](fireDate)

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1, 1])
    }

    func testNewerTimerCanReplaceOlderScheduledRepublish() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()
        republishers[0](scheduler.now.advanced(by: .seconds(1)))

        subject.send(2)
        scheduler.advance()
        republishers[1](scheduler.now.advanced(by: .seconds(2)))

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 2])

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 2, 2])
    }

    func testOlderRetainedTimerCanReplaceNewerScheduledRepublish() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        subject.send(2)
        scheduler.advance()

        republishers[1](scheduler.now.advanced(by: .seconds(2)))
        republishers[0](scheduler.now.advanced(by: .seconds(1)))

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 2, 2])

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1, 2, 2])
    }

    func testRepublishedOutputReceivesNewTimerThatCanRepublishAgain() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()
        var timerNows = [DispatchQueue.SchedulerTimeType]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    timerNows.append(timer.now)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        let firstNow = scheduler.now
        republishers[0](firstNow.advanced(by: .seconds(1)))

        scheduler.advance(by: .seconds(1))
        let secondNow = scheduler.now

        republishers[1](secondNow.advanced(by: .seconds(1)))

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1, 1, 1])
        XCTAssertEqual(timerNows, [firstNow, secondNow, scheduler.now])
    }

    func testCompletionInvalidatesPendingRepublish() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()
        var didFinish = false

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in didFinish = true },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        subject.send(completion: .finished)
        scheduler.advance()

        XCTAssertTrue(didFinish)

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1])
    }

    func testFailureInvalidatesPendingRepublish() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, TestError>()
        var values = [Int]()
        var republishers = [Republisher]()
        var completion: Subscribers.Completion<TestError>?

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { completion = $0 },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        subject.send(completion: .failure(.failed))
        scheduler.advance()

        XCTAssertEqual(completion, .failure(.failed))

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1])
    }

    func testCancellationInvalidatesPendingRepublish() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        subscription.cancel()

        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1])
    }

    func testRetainedTimerDoesNotRepublishAfterCancellation() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )

        subject.send(1)
        scheduler.advance()

        subscription.cancel()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1])
    }

    func testRetainedTimerDoesNotRepublishAfterCompletion() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()

        let subscription = subject
            .againAt(scheduler: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value, timer in
                    values.append(value)
                    republishers.append { timer.republish(at: $0) }
                }
            )
        defer { subscription.cancel() }

        subject.send(1)
        scheduler.advance()

        subject.send(completion: .finished)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))
        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(values, [1])
    }

    func testUpstreamOutputsDropsEarlierOutputWhileThereIsNoDemand() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var upstreamSubscription: Subscription?

        let subscriber = AnySubscriber<
            Publishers.AgainAt<PassthroughSubject<Int, Never>, TestSchedulerOf<DispatchQueue>>
                .Output,
            Never
        >(
            receiveSubscription: { subscription in
                upstreamSubscription = subscription
                subscription.request(.max(1))
            },
            receiveValue: { value, _ in
                values.append(value)
                return .none
            },
            receiveCompletion: { _ in XCTFail("Should not complete") }
        )

        subject
            .againAt(scheduler: scheduler)
            .receive(subscriber: subscriber)

        subject.send(1)
        subject.send(2)
        subject.send(3)

        scheduler.advance()

        XCTAssertEqual(values, [1])

        upstreamSubscription?.request(.max(1))
        scheduler.advance()

        XCTAssertEqual(values, [1, 3])
    }

    func testNewerUpstreamOutputReplacesPendingRepublishWithoutDemand() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var republishers = [Republisher]()
        var upstreamSubscription: Subscription?

        let subscriber = AnySubscriber<
            Publishers.AgainAt<PassthroughSubject<Int, Never>, TestSchedulerOf<DispatchQueue>>
                .Output,
            Never
        >(
            receiveSubscription: { subscription in
                upstreamSubscription = subscription
                subscription.request(.max(1))
            },
            receiveValue: { value, timer in
                values.append(value)
                republishers.append { timer.republish(at: $0) }
                return .none
            },
            receiveCompletion: { _ in XCTFail("Should not complete") }
        )

        subject
            .againAt(scheduler: scheduler)
            .receive(subscriber: subscriber)

        subject.send(1)
        scheduler.advance()

        republishers[0](scheduler.now.advanced(by: .seconds(1)))

        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values, [1])

        subject.send(2)
        scheduler.advance()
        XCTAssertEqual(values, [1])

        upstreamSubscription?.request(.max(1))
        scheduler.advance()

        XCTAssertEqual(values, [1, 2])
    }

    func testPendingValueIsDroppedWhenCompletionArrivesWithoutDemand() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var didFinish = false

        let subscriber = AnySubscriber<
            Publishers.AgainAt<PassthroughSubject<Int, Never>, TestSchedulerOf<DispatchQueue>>
                .Output,
            Never
        >(
            receiveSubscription: { _ in },
            receiveValue: { value, _ in
                values.append(value)
                return .none
            },
            receiveCompletion: { _ in didFinish = true }
        )

        subject
            .againAt(scheduler: scheduler)
            .receive(subscriber: subscriber)

        subject.send(1)
        subject.send(completion: .finished)

        scheduler.advance()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(values, [])
    }

    func testPendingValueIsDroppedWhenFailureArrivesWithoutDemand() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, TestError>()
        var values = [Int]()
        var completion: Subscribers.Completion<TestError>?

        let subscriber = AnySubscriber<
            Publishers.AgainAt<
                PassthroughSubject<Int, TestError>,
                TestSchedulerOf<DispatchQueue>
            >.Output,
            TestError
        >(
            receiveSubscription: { _ in },
            receiveValue: { value, _ in
                values.append(value)
                return .none
            },
            receiveCompletion: { completion = $0 }
        )

        subject
            .againAt(scheduler: scheduler)
            .receive(subscriber: subscriber)

        subject.send(1)
        subject.send(completion: .failure(.failed))

        scheduler.advance()

        XCTAssertEqual(completion, .failure(.failed))
        XCTAssertEqual(values, [])
    }

    func testPendingValueIsDeliveredBeforeCompletionWhenDemandExists() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<Int, Never>()
        var values = [Int]()
        var didFinish = false

        let subscriber = AnySubscriber<
            Publishers.AgainAt<PassthroughSubject<Int, Never>, TestSchedulerOf<DispatchQueue>>
                .Output,
            Never
        >(
            receiveSubscription: { subscription in
                subscription.request(.max(1))
            },
            receiveValue: { value, _ in
                values.append(value)
                return .none
            },
            receiveCompletion: { _ in didFinish = true }
        )

        subject
            .againAt(scheduler: scheduler)
            .receive(subscriber: subscriber)

        subject.send(1)
        subject.send(completion: .finished)

        scheduler.advance()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(values, [1])
    }
}

private typealias Republisher = (DispatchQueue.SchedulerTimeType) -> Void
private typealias DateRepublisher = (Date) -> Void

private enum TestError: Error, Equatable {
    case failed
}

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

    func testBufferedValuesRespectFirstSubscriberDemand() throws {
        let subject = BufferPassthroughSubject<Int, Never>()
        subject.send(0)
        subject.send(1)
        subject.send(2)

        let subscriber = BufferManualDemandSubscriber<Int, Never>(initialDemand: .max(1))
        subject.subscribe(subscriber)

        XCTAssertEqual([0], subscriber.values)
        XCTAssertEqual([], subscriber.completions)

        subscriber.subscription?.request(.max(1))
        subject.send(3)

        XCTAssertEqual([0, 3], subscriber.values)
    }

    func testBufferedCompletionWithoutValuesIsDeliveredToFirstSubscriber() throws {
        let subject = BufferPassthroughSubject<Int, Never>()
        subject.send(completion: .finished)

        let ex = subject.expectToFinish(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testValuesSentAfterBufferedCompletionAreIgnored() throws {
        let subject = BufferPassthroughSubject<Int, Never>()

        subject.send(0)
        subject.send(completion: .finished)
        subject.send(1)

        let ex = subject.expectOutput([0], expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testRepeatedCompletionAfterPassingThroughIsOnlyDeliveredOnce() throws {
        let subject = BufferPassthroughSubject<Int, Never>()

        var completions = 0
        let subscription = subject.sink(
            receiveCompletion: { _ in completions += 1 },
            receiveValue: { _ in }
        )

        subject.send(completion: .finished)
        subject.send(completion: .finished)

        XCTAssertEqual(1, completions)
        subscription.cancel()
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

    func testDoesNotPassThroughValuesReceivedAfterFailure() throws {
        let subject = BufferPassthroughSubject<Int, TestError>()

        subject.send(completion: .failure(.error))
        subject.send(0)

        let bufferEx = subject.expectFailure(.error, failsOnOutput: true)

        subject.send(1)

        let noOutputEx = subject.expectFailure(.error, failsOnOutput: true)

        wait(for: [bufferEx, noOutputEx], timeout: 0.1)
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

private final class BufferManualDemandSubscriber<Input, Failure: Error>: Subscriber {
    var subscription: Subscription?
    private(set) var values = [Input]()
    private(set) var completions = [Subscribers.Completion<Failure>]()

    private let initialDemand: Subscribers.Demand
    private let demandOnValue: Subscribers.Demand

    init(
        initialDemand: Subscribers.Demand,
        demandOnValue: Subscribers.Demand = .none
    ) {
        self.initialDemand = initialDemand
        self.demandOnValue = demandOnValue
    }

    func receive(subscription: Subscription) {
        self.subscription = subscription
        subscription.request(initialDemand)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        values.append(input)
        return demandOnValue
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        completions.append(completion)
    }
}

import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class InputStreamPublisherTests: XCTestCase {
    func testInputStreamPublisherWithData() throws {
        let data = Data("Hello!".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
            [111, 33],
        ]

        let ex = data
            .publisher(maxChunkSize: 2)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithEmptyDataFinishesWithoutOutput() throws {
        let data = Data()

        let ex = data
            .publisher(maxChunkSize: 2)
            .expectToFinish(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithZeroChunkSizeFinishesWithoutOutput() throws {
        let data = Data("Hello!".utf8)

        let ex = data
            .publisher(maxChunkSize: 0)
            .expectToFinish(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherPublishesMoreChunksWhenAdditionalDemandIsRequested() throws {
        let data = Data("Hello".utf8)
        let subscriber = InputStreamManualSubscriber(initialDemand: .max(1))

        data
            .publisher(maxChunkSize: 2)
            .receive(subscriber: subscriber)

        XCTAssertEqual(
            [
                Array("He".utf8),
            ],
            subscriber.values
        )
        XCTAssertTrue(subscriber.completions.isEmpty)

        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(
            [
                Array("He".utf8),
                Array("ll".utf8),
            ],
            subscriber.values
        )
        XCTAssertTrue(subscriber.completions.isEmpty)

        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(
            [
                Array("He".utf8),
                Array("ll".utf8),
                Array("o".utf8),
            ],
            subscriber.values
        )
        XCTAssertTrue(subscriber.completions.isEmpty)

        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(1, subscriber.completions.count)

        guard case .finished? = subscriber.completions.first
        else { return XCTFail("Expected finished completion") }
    }

    func testInputStreamPublisherUsesAdditionalDemandReturnedBySubscriber() throws {
        let data = Data("Hello".utf8)
        let subscriber = InputStreamManualSubscriber(
            initialDemand: .max(1),
            demandOnValue: .max(1)
        )

        data
            .publisher(maxChunkSize: 2)
            .receive(subscriber: subscriber)

        XCTAssertEqual(
            [
                Array("He".utf8),
                Array("ll".utf8),
                Array("o".utf8),
            ],
            subscriber.values
        )
        XCTAssertEqual(1, subscriber.completions.count)

        guard case .finished? = subscriber.completions.first
        else { return XCTFail("Expected finished completion") }
    }

    func testInputStreamPublisherWithLessData() throws {
        let data = Data("Hello".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
            [111],
        ]

        let ex = Publishers.InputStream(data: data, maxChunkSize: 2)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithValidURL() throws {
        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("testInputStreamPublisherWithValidURL-\(arc4random())")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("text.txt")
        try Data("Hello!".utf8).write(to: url, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let expectedOutput: [[UInt8]] = [
            [72, 101, 108],
            [108, 111, 33],
        ]

        let ex = url
            .publisher(maxChunkSize: 3)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamURLPublisherWithEmptyFileFinishesWithoutOutput() throws {
        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "testInputStreamURLPublisherWithEmptyFileFinishesWithoutOutput"
            )

        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: url, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let ex = url
            .publisher(maxChunkSize: 3)
            .expectToFinish(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherFailsForInvalidURL() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("this-folder-does-not-exist")
            .appendingPathComponent("this-file-does-not-exist-\(arc4random()).dat")

        let ex = Publishers.InputStream(url: url, maxChunkSize: 1)
            .expectAnyFailure(failsOnOutput: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherOnlyProvidesAsManyChunksAsRequested() throws {
        let data = Data("Hello!".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
        ]

        var receivedOutput: [[UInt8]] = []

        let outputEx = expectation(description: "Should have received two chunks")
        outputEx.expectedFulfillmentCount = 2

        let noCompletionEx = expectation(description: "Should not have received a completion")
        noCompletionEx.isInverted = true

        let sub = AnySubscriber<[UInt8], Error>(
            receiveSubscription: { $0.request(.max(2)) },
            receiveValue: { bytes in
                receivedOutput.append(bytes)
                outputEx.fulfill()
                return .none
            },
            receiveCompletion: { _ in noCompletionEx.fulfill() }
        )

        let pub = Publishers.InputStream(data: data, maxChunkSize: 2)
        pub.subscribe(sub)

        wait(for: [outputEx], timeout: 2)
        wait(for: [noCompletionEx], timeout: 0.1)

        XCTAssertEqual(expectedOutput, receivedOutput)
    }

    func testInputStreamDoesNotReceiveFinishWhenCancelled() throws {
        class Box { var subscription: AnyObject? }
        let box = Box()

        let data = Data("Hello!".utf8)

        let expectedOutput: [UInt8] = [72, 101]

        let outputEx = expectation(description: "Should have received one chunk")
        let completionEx = expectation(description: "Should not have finished")
        completionEx.isInverted = true

        let subscriber = AnySubscriber<[UInt8], Error>(
            receiveSubscription: { sub in
                box.subscription = sub as AnyObject
                sub.request(.max(1))
            },
            receiveValue: { bytes in
                XCTAssertEqual(expectedOutput, bytes)
                outputEx.fulfill()
                (box.subscription as? Cancellable)?.cancel()
                return .max(1)
            },
            receiveCompletion: { _ in completionEx.fulfill() }
        )

        let pub = Publishers.InputStream(data: data, maxChunkSize: 2)
        pub.subscribe(subscriber)

        wait(for: [outputEx], timeout: 2)
        wait(for: [completionEx], timeout: 0.1)
    }
}

private final class InputStreamManualSubscriber: Subscriber {
    typealias Input = [UInt8]
    typealias Failure = Error

    var subscription: Subscription?
    private(set) var values = [[UInt8]]()
    private(set) var completions = [Subscribers.Completion<Error>]()

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

    func receive(_ input: [UInt8]) -> Subscribers.Demand {
        values.append(input)
        return demandOnValue
    }

    func receive(completion: Subscribers.Completion<Error>) {
        completions.append(completion)
    }
}

import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class StreamSubscriberTests: XCTestCase {
    private var buffer: UnsafeMutablePointer<UInt8>!
    private let bufferCapacity: Int = 10

    private var bytes: [UInt8] {
        (0..<bufferCapacity).map { buffer[$0] }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)
        buffer.initialize(repeating: 0, count: bufferCapacity)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        buffer.deinitialize(count: bufferCapacity)
        buffer.deallocate()
    }

    func testStreamSubscriberWithData() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should have received 6 bytes")
        outputEx.expectedFulfillmentCount = 6
        let completionEx = expectation(description: "Should have received completion")
        let demandEx = expectation(description: "Should have received 7 demands")
        demandEx.expectedFulfillmentCount = 7

        var outputIndex = 0
        let sub = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptionEx.fulfill() },
                receiveRequest: { demand in
                    XCTAssertEqual(.max(1), demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity,
                receiveValue: { (bytesCount) in
                    XCTAssertEqual(1, bytesCount)
                    outputIndex += 1
                    outputEx.fulfill()
                },
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        completionEx.fulfill()
                    case let .failure(error):
                        XCTFail("Should not have received error: \(error.localizedDescription)")
                    }
                }
            )

        defer { sub.cancel() }

        wait(for: [subscriptionEx], timeout: 2)

        input.forEach { subject.send([$0]) }
        subject.send(completion: .finished)

        wait(for: [outputEx, completionEx, demandEx], timeout: 2)

        XCTAssertEqual(
            [72, 101, 108, 108, 111, 33, 0, 0, 0, 0] as [UInt8],
            bytes
        )
    }

    func testStreamSubscriberWithTooMuchData() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [
            72, 101, 108, 108, 111, 33, // Hello!
            72, 101, 108, 108, 111, 33, // Hello!
        ]

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should have received 10 bytes")
        outputEx.expectedFulfillmentCount = bufferCapacity
        let completionEx = expectation(description: "Should not have received completion")
        completionEx.isInverted = true
        var cancelEx: XCTestExpectation? = expectation(description: "Should have received cancel")
        cancelEx?.isInverted = true
        let demandEx = expectation(description: "Should have received 10 demands")
        demandEx.expectedFulfillmentCount = bufferCapacity

        var outputIndex = 0
        let sub = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptionEx.fulfill() },
                receiveCancel: { cancelEx?.fulfill() },
                receiveRequest: { demand in
                    let expected = outputIndex <= self.bufferCapacity ?
                        Subscribers.Demand.max(1) :
                        .none
                    XCTAssertEqual(expected, demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity,
                receiveValue: { (bytesCount) in
                    XCTAssertEqual(1, bytesCount)
                    outputIndex += 1
                    outputEx.fulfill()
                },
                receiveCompletion: { _ in completionEx.fulfill() }
            )

        defer { sub.cancel() }

        wait(for: [subscriptionEx], timeout: 2)

        input.forEach { subject.send([$0]) }

        wait(for: [outputEx, demandEx], timeout: 2)

        wait(for: [completionEx, cancelEx!], timeout: 0.1)
        cancelEx = nil // `defer { sub.cancel() }` might trigger this inverted exception

        XCTAssertEqual(
            [72, 101, 108, 108, 111, 33, 72, 101, 108, 108,] as [UInt8],
            bytes
        )
    }

    func testStreamSubscriberDataSentBeforeSubscribingToBufferedSubject() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let outputEx = expectation(description: "Should have received 6 bytes")
        outputEx.expectedFulfillmentCount = 6
        let completionEx = expectation(description: "Should have received completion")
        let demandEx = expectation(description: "Should have received 7 demands")
        demandEx.expectedFulfillmentCount = 7

        var outputIndex = 0
        let sub = subject
            .buffer(size: bufferCapacity, prefetch: .byRequest, whenFull: .dropOldest)
            .handleEvents(
                receiveSubscription: { _ in
                    input.forEach { subject.send([$0]) }
                    subject.send(completion: .finished)
                },
                receiveRequest: { demand in
                    XCTAssertEqual(.max(1), demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity,
                receiveValue: { bytesCount in
                    XCTAssertEqual(1, bytesCount)
                    outputIndex += 1
                    outputEx.fulfill()
                },
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        completionEx.fulfill()
                    case let .failure(error):
                        XCTFail("Should not have received error: \(error.localizedDescription)")
                    }
                }
            )

        defer { sub.cancel() }

        wait(for: [outputEx, completionEx, demandEx], timeout: 2)

        XCTAssertEqual(
            [72, 101, 108, 108, 111, 33, 0, 0, 0, 0] as [UInt8],
            bytes
        )
    }

    func testStreamSubscriberSucceedsWithValidURL() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("testStreamSubscriberSucceedsWithValidURL-\(arc4random())")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("text.txt")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should have received 6 bytes")
        outputEx.expectedFulfillmentCount = 6
        let completionEx = expectation(description: "Should have received completion")

        let sub = subject
            .handleEvents(receiveSubscription: { _ in subscriptionEx.fulfill() })
            .stream(
                toURL: url,
                append: false,
                receiveValue: { _ in outputEx.fulfill() },
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        completionEx.fulfill()
                    case let .failure(error):
                        XCTFail("Should not have received error: \(error.localizedDescription)")
                    }
                }
            )

        defer { sub.cancel() }

        wait(for: [subscriptionEx], timeout: 2)

        input.forEach { subject.send([$0]) }
        subject.send(completion: .finished)

        wait(for: [outputEx, completionEx], timeout: 2)

        XCTAssertEqual("Hello!", try String(contentsOf: url))
    }

    func testStreamSubscriberFailsForInvalidURL() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("this-folder-does-not-exist")
            .appendingPathComponent("this-file-does-not-exist-\(arc4random()).dat")

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should have received 10 bytes")
        outputEx.isInverted = true
        let failureEx = expectation(description: "Should not have received failure")
        failureEx.isInverted = true
        var cancelEx: XCTestExpectation? = expectation(description: "Should not have received cancel")
        let demandEx = expectation(description: "Should not have received demand")
        demandEx.isInverted = true

        let sub = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptionEx.fulfill() },
                receiveCancel: { cancelEx?.fulfill() },
                receiveRequest: { _ in demandEx.fulfill() }
            )
            .stream(
                toURL: url,
                append: false,
                receiveValue: { _ in outputEx.fulfill() },
                receiveCompletion: { _ in failureEx.fulfill() }
            )

        defer { sub.cancel() }

        wait(for: [subscriptionEx, cancelEx!], timeout: 2)

        subject.send([72])

        wait(for: [outputEx, failureEx, demandEx], timeout: 0.1)
        cancelEx = nil
    }

    func testUnretainedStreamSubscriberNeverReceivesOutputOrCompletion() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should not have received output")
        outputEx.isInverted = true
        let completionEx = expectation(description: "Should not have received completion")
        completionEx.isInverted = true
        let demandEx = expectation(description: "Should have received demand")

        let _ = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptionEx.fulfill() },
                receiveRequest: { demand in
                    XCTAssertEqual(.max(1), demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity,
                receiveValue: { _ in outputEx.fulfill() },
                receiveCompletion: { _ in completionEx.fulfill() }
            )

        wait(for: [subscriptionEx, demandEx], timeout: 2)

        subject.send([42])
        subject.send(completion: .finished)

        wait(for: [outputEx, completionEx], timeout: 0.1)

        XCTAssertEqual([0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as [UInt8], bytes)
    }

    func testCancelledStreamSubscriberDoesNotReceivesFurtherOutputOrCompletion() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let outputEx = expectation(description: "Should have received one value")
        let completionEx = expectation(description: "Should not have received completion")
        completionEx.isInverted = true
        let cancelEx = expectation(description: "Should have received cancel")
        let demandEx = expectation(description: "Should have received demand")
        demandEx.assertForOverFulfill = false

        let sub = subject
            .handleEvents(
                receiveCancel: { cancelEx.fulfill() },
                receiveRequest: { demand in
                    XCTAssertEqual(.max(1), demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity,
                receiveValue: { _ in outputEx.fulfill() },
                receiveCompletion: { _ in completionEx.fulfill() }
            )

        wait(for: [demandEx], timeout: 2)

        subject.send([42])

        sub.cancel()

        subject.send([127])
        subject.send(completion: .finished)

        wait(for: [cancelEx], timeout: 2)
        wait(for: [outputEx, completionEx], timeout: 0.1)

        XCTAssertEqual([42, 0, 0, 0, 0, 0, 0, 0, 0, 0] as [UInt8], bytes)
    }
}

import Combine
import CombineExtensions
import CombineTestExtensions
import XCTest

class OutputStreamPublisherTests: XCTestCase {
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

    func testWithData() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let subscriptionEx = expectation(description: "Should have received subscription")
        let outputEx = expectation(description: "Should have received 6 bytes")
        outputEx.expectedFulfillmentCount = 6
        let completionEx = expectation(description: "Should have received completion")
        let demandEx = expectation(description: "Should have received 1 unlimited demand")

        var outputIndex = 0
        let sub = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptionEx.fulfill() },
                receiveRequest: { demand in
                    XCTAssertEqual(.unlimited, demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity
            )
            .sink(
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

    func testWithMultipleByteChunks() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let input: [[UInt8]] = [
            [72, 105, 33], // Hi!
            [72, 105, 33], // Hi!
        ]

        let ex = subject
            .stream(toBuffer: buffer, capacity: bufferCapacity)
            .expectOutput([3, 3], expectToFinish: true)

        input.forEach { subject.send($0) }
        subject.send(completion: .finished)

        wait(for: [ex], timeout: 2)

        XCTAssertEqual([72, 105, 33, 72, 105, 33, 0, 0, 0, 0] as [UInt8], bytes)
    }

    func testWithTooMuchData() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [
            72, 101, 108, 108, 111, 33, // Hello!
            72, 101, 108, 108, 111, 33, // Hello!
        ]

        let cancelEx = expectation(description: "Should have received cancel")

        var expectedOutputCount = 10
        let ex = subject
            .handleEvents(receiveCancel: { cancelEx.fulfill() })
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity
            )
            .expectOutputAndFailure(
                { value in
                    expectedOutputCount -= value
                    return expectedOutputCount == 0 ? .finished : .moreExpected
                },
                failureEvaluator: { error in
                    let nserror = error as NSError
                    XCTAssertEqual(NSPOSIXErrorDomain, nserror.domain)
                    XCTAssertEqual(12, nserror.code)
                }
            )


        input.forEach { subject.send([$0]) }

        wait(for: [cancelEx, ex], timeout: 2)

        XCTAssertEqual(
            [72, 101, 108, 108, 111, 33, 72, 101, 108, 108,] as [UInt8],
            bytes
        )
    }

    func testDataSentBeforeSubscribingToBufferedSubject() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let ex = subject
            .buffer(size: bufferCapacity, prefetch: .byRequest, whenFull: .dropOldest)
            .handleEvents(
                receiveSubscription: { _ in
                    input.forEach { subject.send([$0]) }
                    subject.send(completion: .finished)
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity
            )
            .expectOutput((0..<6).map { _ in 1 }, expectToFinish: true)

        wait(for: [ex], timeout: 2)

        XCTAssertEqual(
            [72, 101, 108, 108, 111, 33, 0, 0, 0, 0] as [UInt8],
            bytes
        )
    }

    func testSucceedsWithValidURL() throws {
        let subject = PassthroughSubject<[UInt8], Error>()
        let input: [UInt8] = [72, 101, 108, 108, 111, 33] // Hello!

        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("testStreamSubscriberSucceedsWithValidURL-\(arc4random())")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("text.txt")

        let ex = subject
            .stream(
                toURL: url,
                append: false
            )
            .expectToFinish()

        input.forEach { subject.send([$0]) }
        subject.send(completion: .finished)

        wait(for: [ex], timeout: 2)

        XCTAssertEqual("Hello!", try String(contentsOf: url))
    }

    func testFailsForInvalidURL() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("this-folder-does-not-exist", isDirectory: true)
            .appendingPathComponent(
                "this-file-does-not-exist-\(arc4random()).dat",
                isDirectory: false
            )

        let cancelEx = expectation(description: "Should have received cancel")
        let ex = subject
            .handleEvents(receiveCancel: { cancelEx.fulfill() })
            .stream(
                toURL: url,
                append: false
            )
            .expectFailure { error in
                let nserror = error as NSError
                XCTAssertEqual(NSPOSIXErrorDomain, nserror.domain)
                XCTAssertEqual(2, nserror.code)
            }

        subject.send([72])

        wait(for: [ex, cancelEx], timeout: 0.1)
    }

    func testUnretainedPublisherNeverPublishesOutputOrCompletion() throws {
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
                    XCTAssertEqual(.unlimited, demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity
            )
            .sink(
                receiveValue: { _ in outputEx.fulfill() },
                receiveCompletion: { _ in completionEx.fulfill() }
            )

        wait(for: [subscriptionEx, demandEx], timeout: 2)

        subject.send([42])
        subject.send(completion: .finished)

        wait(for: [outputEx, completionEx], timeout: 0.1)

        XCTAssertEqual([0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as [UInt8], bytes)
    }

    func testCancelledPublisherDoesNotPublishFurtherOutputOrCompletion() throws {
        let subject = PassthroughSubject<[UInt8], Error>()

        let outputEx = expectation(description: "Should have received one value")
        let completionEx = expectation(description: "Should not have received completion")
        completionEx.isInverted = true
        let cancelEx = expectation(description: "Should have received cancel")
        let demandEx = expectation(description: "Should have received demand")

        let sub = subject
            .handleEvents(
                receiveCancel: { cancelEx.fulfill() },
                receiveRequest: { demand in
                    XCTAssertEqual(.unlimited, demand)
                    demandEx.fulfill()
                }
            )
            .stream(
                toBuffer: buffer,
                capacity: bufferCapacity
            )
            .sink(
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

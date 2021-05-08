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

        let ex = InputStreamPublisher(data: data, maxChunkLength: 2)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherWithLessData() throws {
        let data = Data("Hello".utf8)

        let expectedOutput: [[UInt8]] = [
            [72, 101],
            [108, 108],
            [111],
        ]

        let ex = InputStreamPublisher(data: data, maxChunkLength: 2)
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

        let ex = InputStreamPublisher(url: url, maxChunkLength: 3)
            .expectOutput(expectedOutput, expectToFinish: true)

        wait(for: [ex], timeout: 2)
    }

    func testInputStreamPublisherFailsForInvalidURL() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("this-folder-does-not-exist")
            .appendingPathComponent("this-file-does-not-exist-\(arc4random()).dat")

        let ex = InputStreamPublisher(url: url, maxChunkLength: 1)
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

        let pub = InputStreamPublisher(data: data, maxChunkLength: 2)
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

        let pub = InputStreamPublisher(data: data, maxChunkLength: 2)
        pub.subscribe(subscriber)

        wait(for: [outputEx], timeout: 2)
        wait(for: [completionEx], timeout: 0.1)
    }

    func testInputStreamWaitsForMeasuredSinkDemand() throws {
        let data = Data("Hello!".utf8)

        var receivedOutput: [[UInt8]] = []

        let ex1 = expectation(description: "Should have received first two chunks")
        let ex2 = expectation(description: "Should have received second two chunks")
        let ex3 = expectation(description: "Should have received third two chunks")
        let finishedEx = expectation(description: "Should have completed")

        let sub = InputStreamPublisher(data: data, maxChunkLength: 2)
            .measuredSink(
                initialDemand: .max(1),
                receiveValue: { value in
                    switch receivedOutput.count {
                    case 0:
                        receivedOutput.append(value)
                        ex1.fulfill()

                    case 1:
                        receivedOutput.append(value)
                        ex2.fulfill()

                    case 2:
                        receivedOutput.append(value)
                        ex3.fulfill()

                    default:
                        XCTFail("Should only have received three chunks")
                    }

                    return .none
                },
                receiveCompletion: { completion in
                    switch completion {
                    case .finished: finishedEx.fulfill()
                    case let .failure(error): XCTFail("Should not have failed: \(error)")
                    }
                }
            )
        defer { sub.cancel() }

        wait(for: [ex1], timeout: 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual([[72, 101]], receivedOutput)

        sub.request(demand: .max(1))
        wait(for: [ex2], timeout: 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual([[72, 101], [108, 108]], receivedOutput)

        sub.request(demand: .max(1))
        wait(for: [ex3], timeout: 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual([[72, 101], [108, 108], [111, 33]], receivedOutput)

        sub.request(demand: .max(1))
        wait(for: [finishedEx], timeout: 2)
        XCTAssertEqual([[72, 101], [108, 108], [111, 33]], receivedOutput)
    }
}

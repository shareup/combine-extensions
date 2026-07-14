import Combine
import Dispatch
import Foundation

/// A scheduler that measures time using the wall clock and executes work on a dispatch queue.
///
/// Unlike `DispatchQueue`'s `Scheduler` conformance, scheduled time advances while the system
/// sleeps. Work whose deadline passes while the process cannot run is submitted to `queue` as
/// soon as the process can run again.
public struct WallClockScheduler: Scheduler, Sendable {
    public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {
        public typealias Stride = RunLoop.SchedulerTimeType.Stride

        public let date: Date

        public init(_ date: Date) {
            self.date = date
        }

        public func distance(to other: Self) -> Stride {
            Stride(other.date.timeIntervalSince(date))
        }

        public func advanced(by stride: Stride) -> Self {
            Self(date.addingTimeInterval(stride.timeInterval))
        }
    }

    public typealias SchedulerOptions = DispatchQueue.SchedulerOptions

    public let queue: DispatchQueue

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    public var now: SchedulerTimeType {
        SchedulerTimeType(Date())
    }

    public var minimumTolerance: SchedulerTimeType.Stride {
        .zero
    }

    public func schedule(
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        let options = options ?? SchedulerOptions()
        scheduleOnQueue(options: options, action)
    }

    public func schedule(
        after date: SchedulerTimeType,
        tolerance _: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        let options = options ?? SchedulerOptions()
        options.group?.enter()

        queue.asyncAfter(
            wallDeadline: date.dispatchWallTime,
            qos: options.qos,
            flags: options.flags
        ) {
            defer { options.group?.leave() }
            action()
        }
    }

    public func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        let options = options ?? SchedulerOptions()
        return WallClockRepeatingTimer(
            queue: queue,
            deadline: date.dispatchWallTime,
            interval: interval.dispatchTimeInterval(minimumNanoseconds: 1),
            tolerance: tolerance.dispatchTimeInterval(minimumNanoseconds: 0),
            options: options,
            action: action
        )
    }

    private func scheduleOnQueue(
        options: SchedulerOptions,
        _ action: @escaping () -> Void
    ) {
        options.group?.enter()
        queue.async(
            qos: options.qos,
            flags: options.flags
        ) {
            defer { options.group?.leave() }
            action()
        }
    }
}

public extension WallClockScheduler.SchedulerTimeType {
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date < rhs.date
    }
}

private final class WallClockRepeatingTimer: Cancellable, @unchecked Sendable {
    private let source: DispatchSourceTimer

    init(
        queue: DispatchQueue,
        deadline: DispatchWallTime,
        interval: DispatchTimeInterval,
        tolerance: DispatchTimeInterval,
        options: WallClockScheduler.SchedulerOptions,
        action: @escaping () -> Void
    ) {
        source = DispatchSource.makeTimerSource(queue: queue)
        source.setEventHandler(qos: options.qos, flags: options.flags) {
            options.group?.enter()
            defer { options.group?.leave() }
            action()
        }
        source.schedule(
            wallDeadline: deadline,
            repeating: interval,
            leeway: tolerance
        )
        source.activate()
    }

    deinit {
        cancel()
    }

    func cancel() {
        source.cancel()
    }
}

private extension WallClockScheduler.SchedulerTimeType {
    var dispatchWallTime: DispatchWallTime {
        guard date > Date() else { return .now() }

        let interval = date.timeIntervalSince1970
        guard interval.isFinite,
              interval < TimeInterval(UInt64.max) / nanosecondsPerSecond
        else { return .distantFuture }

        var seconds = Int(floor(interval))
        var nanoseconds = Int(
            ((interval - TimeInterval(seconds)) * nanosecondsPerSecond).rounded(.up)
        )

        if nanoseconds >= Int(nanosecondsPerSecond) {
            seconds += 1
            nanoseconds = 0
        }

        return DispatchWallTime(
            timespec: timespec(
                tv_sec: seconds,
                tv_nsec: nanoseconds
            )
        )
    }
}

private extension WallClockScheduler.SchedulerTimeType.Stride {
    func dispatchTimeInterval(minimumNanoseconds: Int) -> DispatchTimeInterval {
        let rawNanoseconds = (timeInterval * nanosecondsPerSecond).rounded(.up)
        let nanoseconds: Int

        if rawNanoseconds.isNaN || rawNanoseconds <= Double(minimumNanoseconds) {
            nanoseconds = minimumNanoseconds
        } else if !rawNanoseconds.isFinite || rawNanoseconds >= Double(Int.max) {
            nanoseconds = Int.max
        } else {
            nanoseconds = Int(rawNanoseconds)
        }

        return .nanoseconds(nanoseconds)
    }
}

private let nanosecondsPerSecond: Double = 1_000_000_000

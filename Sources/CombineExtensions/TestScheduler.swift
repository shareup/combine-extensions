import Combine
import Foundation

/// A scheduler whose current time and execution can be controlled in a deterministic manner.
///
/// This schedule was taken from `CombineSchedulers` by Point-Free, Inc.
/// https://github.com/pointfreeco/combine-schedulers/blob/main/Sources/CombineSchedulers/TestScheduler.swift
///
public final class TestScheduler<SchedulerTimeType, SchedulerOptions>: Scheduler
where
    SchedulerTimeType: Strideable,
    SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
{
    private var lastSequence: UInt = 0
    public let minimumTolerance: SchedulerTimeType.Stride = .zero
    public private(set) var now: SchedulerTimeType
    private var scheduled: [(sequence: UInt, date: SchedulerTimeType, action: () -> Void)] = []

    public init(now: SchedulerTimeType) {
        self.now = now
    }

    public func advance(by stride: SchedulerTimeType.Stride = .zero) {
        let finalDate = self.now.advanced(by: stride)

        while self.now <= finalDate {
            self.scheduled.sort { ($0.date, $0.sequence) < ($1.date, $1.sequence) }

            guard
                let nextDate = self.scheduled.first?.date,
                finalDate >= nextDate
            else {
                self.now = finalDate
                return
            }

            self.now = nextDate

            while let (_, date, action) = self.scheduled.first, date == nextDate {
                self.scheduled.removeFirst()
                action()
            }
        }
    }

    public func run() {
        while let date = self.scheduled.first?.date {
            self.advance(by: self.now.distance(to: date))
        }
    }

    public func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance _: SchedulerTimeType.Stride,
        options _: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        let sequence = self.nextSequence()

        func scheduleAction(for date: SchedulerTimeType) -> () -> Void {
            return { [weak self] in
                let nextDate = date.advanced(by: interval)
                self?.scheduled.append((sequence, nextDate, scheduleAction(for: nextDate)))
                action()
            }
        }

        self.scheduled.append((sequence, date, scheduleAction(for: date)))

        return AnyCancellable { [weak self] in
            self?.scheduled.removeAll(where: { $0.sequence == sequence })
        }
    }

    public func schedule(
        after date: SchedulerTimeType,
        tolerance _: SchedulerTimeType.Stride,
        options _: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        self.scheduled.append((self.nextSequence(), date, action))
    }

    public func schedule(options _: SchedulerOptions?, _ action: @escaping () -> Void) {
        self.scheduled.append((self.nextSequence(), self.now, action))
    }

    private func nextSequence() -> UInt {
        self.lastSequence += 1
        return self.lastSequence
    }
}

extension DispatchQueue {
    public static var test: TestSchedulerOf<DispatchQueue> {
        .init(now: .init(.init(uptimeNanoseconds: 1)))
    }
}

extension OperationQueue {
    public static var test: TestSchedulerOf<OperationQueue> {
        .init(now: .init(.init(timeIntervalSince1970: 0)))
    }
}

extension RunLoop {
    public static var test: TestSchedulerOf<RunLoop> {
        .init(now: .init(.init(timeIntervalSince1970: 0)))
    }
}


public typealias TestSchedulerOf<Scheduler> = TestScheduler<
    Scheduler.SchedulerTimeType, Scheduler.SchedulerOptions
> where Scheduler: Combine.Scheduler

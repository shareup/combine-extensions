import Combine
import Dispatch

/// A scheduler that executes its work on the main queue as soon as possible.
///
/// This schedule was taken from `CombineSchedulers` by Point-Free, Inc.
/// https://github.com/pointfreeco/combine-schedulers/blob/main/Sources/CombineSchedulers/UIScheduler.swift
///
public struct UIScheduler: Scheduler {
    public typealias SchedulerOptions = Never
    public typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType

    /// The shared instance of the UI scheduler.
    ///
    /// You cannot create instances of the UI scheduler yourself. Use only the shared instance.
    public static let shared = Self()

    public var now: SchedulerTimeType { DispatchQueue.main.now }
    public var minimumTolerance: SchedulerTimeType
        .Stride { DispatchQueue.main.minimumTolerance }

    public func schedule(options _: SchedulerOptions? = nil, _ action: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: key) == value {
            action()
        } else {
            DispatchQueue.main.schedule(action)
        }
    }

    public func schedule(
        after date: SchedulerTimeType,
        tolerance: SchedulerTimeType.Stride,
        options _: SchedulerOptions? = nil,
        _ action: @escaping () -> Void
    ) {
        DispatchQueue.main.schedule(
            after: date,
            tolerance: tolerance,
            options: nil,
            action
        )
    }

    public func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance: SchedulerTimeType.Stride,
        options _: SchedulerOptions? = nil,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        DispatchQueue.main.schedule(
            after: date,
            interval: interval,
            tolerance: tolerance,
            options: nil,
            action
        )
    }

    private init() { _ = setSpecific }
}

private let key = DispatchSpecificKey<UInt8>()
private let value: UInt8 = 0
private var setSpecific: () = { DispatchQueue.main.setSpecific(key: key, value: value) }()

# Combine Extensions

A collection of useful extensions for Apple's [Combine framework](https://developer.apple.com/documentation/combine).

## Features

### Publishers

- [AgainAt](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/AgainAt.swift)
- [AnyConnectablePublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/AnyConnectablePublisher.swift)
- [BufferPassthroughSubject](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/BufferPassthroughSubject.swift)
- [Distinct](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/Distinct.swift)
- [Enumerated](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/Enumerated.swift)
- [InputStreamPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/InputStreamPublisher.swift)
- [MulticastLatest](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/MulticastLatest.swift)
- [OutputStreamPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/OutputStreamPublisher.swift)
- [ReduceLatest](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/ReduceLatest.swift)
- [RetryIf](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/RetryIf.swift)
- [ThrottleWhile](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/ThrottleWhile.swift)

### Extensions

- [Cancellable.onCancel()](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/OnCancel.swift)
- [Publisher.sink()](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/Publisher+Sink.swift)

### Schedulers

- [TestScheduler](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/TestScheduler.swift)
- [UIScheduler](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/UIScheduler.swift)
- [WallClockScheduler](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/WallClockScheduler.swift)

### Thread-safe subscription management

- [KeyedSubscriptionStore](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/KeyedSubscriptionStore.swift)
- [SingleSubscriptionStore](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/SingleSubscriptionStore.swift)

## Usage

Add CombineExtensions to the dependencies section of your package.swift file.

```swift
.package(url: "https://github.com/shareup/combine-extensions.git", from: "6.2.0")
```

## License

CombineExtensions is licensed under the MIT license. It includes code from [Combine Schedulers](https://github.com/pointfreeco/combine-schedulers), which is also licensed under the MIT license.

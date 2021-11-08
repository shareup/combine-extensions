# Combine Extensions

A collection of useful extensions for Apple's [Combine framework](https://developer.apple.com/documentation/combine).

## Features

### Publishers

- [AnyConnectablePublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/AnyConnectablePublisher.swift)
- [BufferPassthroughSubject](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/BufferPassthroughSubject.swift)
- [EnumeratedPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/Enumerated.swift)
- [InputStreamPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/InputStreamPublisher.swift)
- [OutputStreamPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/OutputStreamPublisher.swift)
- [ReduceLatestPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/ReduceLatest.swift)
- [RetryIfPublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/RetryIf.swift)
- [ThrottleWhilePublisher](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/ThrottleWhile.swift)

### Thread-safe subscription management

- [KeyedSubscriptionStore](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/KeyedSubscriptionStore.swift)
- [SingleSubscriptionStore](https://github.com/shareup/combine-extensions/blob/main/Sources/CombineExtensions/SingleSubscriptionStore.swift)

## Usage

Add CombineExtensions to the dependencies section of your package.swift file.

```swift
.package(name: "CombineExtensions", url: "https://github.com/shareup/combine-extensions.git", from: "4.5.0")
```

## License

CombineExtensions is licensed under the MIT license. It includes code from [Combine Schedulers](https://github.com/pointfreeco/combine-schedulers), which is also licensed under the MIT license.

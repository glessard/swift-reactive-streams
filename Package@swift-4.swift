// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "4.4.3"),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.2.1"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.0.2"),
    .package(url: "https://github.com/glessard/deferred.git", from: "4.4.3"),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "Outcome", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: [4,5]
)

// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "4.4.2"),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.2.0"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.0.1"),
    .package(url: "https://github.com/glessard/deferred.git", from: "4.4.2"),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "Outcome", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .version("5")]
)

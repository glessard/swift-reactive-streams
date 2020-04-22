// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "6.2.0"),
    .package(url: "https://github.com/glessard/deferred.git", from: "6.2.3"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .v5]
)

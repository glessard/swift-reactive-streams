// swift-tools-version:4.0

import PackageDescription

#if !swift(>=4.2)
let versions = [4]
#else
let versions = [SwiftVersion.v4, .v4_2]
#endif

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "4.2.0"),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.1.5"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.0.0"),
    .package(url: "https://github.com/glessard/deferred.git", from: "4.3.0"),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "Outcome", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: versions
)

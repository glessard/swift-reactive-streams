// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", .revision("2575543d151c992d7b0e9dd0929ee6f5482cbfdf")),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.2.3"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
    .package(url: "https://github.com/glessard/deferred.git", .revision("742348fb486e6748c79fbaba4128056dccb57733")),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "Outcome", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .v5]
)

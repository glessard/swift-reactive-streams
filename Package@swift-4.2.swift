// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "ReactiveStreams",
  products: [
    .library(name: "ReactiveStreams", targets: ["ReactiveStreams"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", .revision("2ede65e5947d68440778d2d6bbceb1dfdafc6f9a")),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.2.3"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
    .package(url: "https://github.com/glessard/deferred.git", .revision("778450eb125c40403799a909aa3f3f690f1805ac")),
  ],
  targets: [
    .target(name: "ReactiveStreams", dependencies: ["CAtomics", "Outcome", "CurrentQoS", "deferred"]),
    .testTarget(name: "ReactiveStreamsTests", dependencies: ["ReactiveStreams"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .version("5")]
)

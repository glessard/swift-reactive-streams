// swift-tools-version:4.0

import PackageDescription

let name = "ReactiveStreams"

#if swift(>=4.0)

let package = Package(
  name: name,
  products: [
    .library(name: name, targets: [name]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "4.0.0")
  ],
  targets: [
    .target(name: name, dependencies: ["CAtomics"]),
    .testTarget(name: name+"Tests", dependencies: [Target.Dependency(stringLiteral: name)]),
  ],
  swiftLanguageVersions: [3,4]
)

#else


let package = Package(
  name: name,
  targets: [
    Target(name: name),
  ],
  dependencies: [
    .Package(url: "https://github.com/glessard/swift-atomics.git", majorVersion: 4, minor: 0),
  ]
)

#endif


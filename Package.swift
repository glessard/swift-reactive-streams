// swift-tools-version:4.0

import PackageDescription

let name = "ReactiveStreams"

let package = Package(
  name: name,
  products: [
    .library(name: name, targets: [name]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "3.6.0")
  ],
  targets: [
    .target(name: name, dependencies: ["CAtomics"]),
  ],
  swiftLanguageVersions: [4]
)

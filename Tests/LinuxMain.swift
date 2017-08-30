import XCTest
@testable import ReactiveStreamsTests

XCTMain([
  testCase(flatMapTests.allTests),
  testCase(mergeTests.allTests),
  testCase(onRequestTests.allTests),
  testCase(streamTests.allTests),
  testCase(subscriberTests.allTests),
])

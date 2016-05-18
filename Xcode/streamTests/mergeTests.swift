//
//  mergeTests.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
@testable import stream

class mergeTests: XCTestCase
{
  override func setUp()
  {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }

  override func tearDown()
  {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }

  func testMerge1()
  {
    let s = Stream<Int>()

    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectationWithDescription("observation ends \(random())")

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
      }
    }

    for i in 0..<count { s.process(i+1) }
    s.close()

    merged.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge2()
  {
    let s = Stream<Int>()

    let count = 10

    // let q = dispatch_get_global_queue(qos_class_self(), 0)
    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectationWithDescription("observation ends \(random())")

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error):
        e.fulfill()
        if error is StreamCompleted {}
        else { print(error) }
      }
    }

    merged.close()

    for i in 0..<count { s.process(i+1) }
    s.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge3()
  {
    let s = Stream<Int>()

    let count = 0

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectationWithDescription("observation ends \(random())")

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default:
        XCTFail()
      }
    }

    merged.process(Result.error(NSError(domain: "bogus", code: -1, userInfo: nil)))

    for i in 0..<count { s.process(i+1) }
    s.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge4()
  {
    let s = [Stream<Int>(), Stream<Int>()]
    let e = expectationWithDescription("observation ends \(random())")

    let count = 10

    let merged = MergeStream<Int>()
    s.forEach(merged.merge)

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count*s.count)
        if value != count*s.count { print(value) }
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
      }
    }
    merged.close()

    let q = dispatch_get_global_queue(qos_class_self(), 0)
    for stream in s
    {
      dispatch_async(q) {
        for i in 0..<count { stream.process(i+1) }
        stream.close()
      }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge5()
  {
    let s = Stream<Int>()
    let e = expectationWithDescription("observation ends \(random())")
    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)
    merged.onValue { if $0 == count { e.fulfill() } }

    for i in 0..<count { s.process(i+1) }

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let f = expectationWithDescription("observation ends \(random())")

    s.onCompletion { _ in f.fulfill() }
    s.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let g = expectationWithDescription("observation ends \(random())")

    merged.onError { _ in g.fulfill() }
    merged.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge6()
  {
    let s = Stream<Int>()
    let e = expectationWithDescription("observation ends \(random())")
    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)
    merged.onValue { if $0 == count { e.fulfill() } }

    for i in 0..<count { s.process(i+1) }
    s.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let g = expectationWithDescription("observation ends \(random())")

    merged.onCompletion { _ in g.fulfill() }
    merged.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMerge7()
  {
    let s = [Stream<Int>(), Stream<Int>()]
    let e = expectationWithDescription("observation ends \(random())")

    let count = 10

    let merged = MergeStream<Int>()
    s.forEach(merged.merge)
    merged.close()

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == (count + count/2))
        if value != (count + count/2) { print(value) }
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default:
        XCTFail()
      }
    }

    for (n,stream) in s.enumerate()
    {
      for i in 0..<count
      {
        stream.process(Result.value((n+1)*i).map({
          v throws -> Int in
          if v < count { return v }
          throw NSError(domain: "bogus", code: -1, userInfo: nil)
        }))
      }
      stream.close()
      dispatch_barrier_sync(stream.queue) {}
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
}

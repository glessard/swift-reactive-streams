//
//  streamTests.swift
//  streamTests
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
@testable import stream

class streamTests: XCTestCase
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

  func testNotify()
  {
    let events = 10
    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")
    let stream = Stream<Int>()

    stream.notify {
      result in
      switch result
      {
      case .value(let value):
        if value == events { e1.fulfill() }
      case .error(let error):
        if error is StreamCompleted { e2.fulfill() }
      }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testOnValue()
  {
    let events = 10
    let e1 = expectationWithDescription("observation onValue")
    let stream = Stream<Int>()

    stream.onValue {
      v in
      if v == events { e1.fulfill() }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testOnError()
  {
    let e2 = expectationWithDescription("observation onError")
    let stream = Stream<Int>()

    stream.onError {
      error in
      if error is StreamCompleted { e2.fulfill() }
    }

    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testOnComplete()
  {
    let s1 = Stream<Int>()
    s1.onCompletion {
      _ in XCTFail()
    }

    s1.process(Result())

    let e2 = expectationWithDescription("observation onCompletion")
    let s2 = Stream<Int>()
    s2.onCompletion {
      _ in e2.fulfill()
    }
    s2.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMap1()
  {
    let events = 10
    let stream = Stream<Int>()

    let e2 = expectationWithDescription("observation onError")

    var d = Array<Double>()
    let m = stream.map(transform: { 2.0*Double($0) }).map(transform: { d.append($0) }).final()
    m.onError {
      error in
      if let t = error as? StreamCompleted, case .terminated = t
      {
        XCTAssert(d.count == events)
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
    // print(d)
  }

  func testMap2()
  {
    let stream = Stream<Int>()

    let events = 10
    let limit = 5

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.map {
      i throws -> Int in
      if i < limit { return i+1 }
      throw NSError(domain: "bogus", code: -1, userInfo: nil)
    }
    m.onValue {
      v in
      if v == limit { e1.fulfill() }
    }
    m.onError {
      error in
      let error = error as NSError
      if error.domain == "bogus" { e2.fulfill() }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMap3()
  {
    let stream = Stream<Int>()

    let events = 10
    let limit = 5

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.map {
      r -> Result<Int> in
      r.flatMap {
        i in
        if i < limit { return Result.value(i+1) }
        return Result.error(NSError(domain: "bogus", code: -1, userInfo: nil))
      }
    }
    m.onValue {
      v in
      if v == limit { e1.fulfill() }
    }
    m.onError {
      error in
      let error = error as NSError
      if error.domain == "bogus" { e2.fulfill() }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNextN()
  {
    let stream = Stream<Int>()

    let events = 100
    let limit = 5

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.next(count: limit)
    m.notify {
      result in
      switch result
      {
      case .value(let value):
        if value == limit { e1.fulfill() }
      case .error(let error):
        if (error is StreamCompleted) { e2.fulfill() }
      }
    }

    XCTAssert(stream.requested == Int64(limit))

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNextTruncated()
  {
    let stream = Stream<Int>()

    let events = 100
    let limit = 50
    let truncation = 5

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.next(count: limit)
    let t = m.map {
      i throws -> Int in
      if i <= truncation { return i }
      throw NSError(domain: "bogus", code: -1, userInfo: nil)
    }
    t.notify {
      result in
      switch result
      {
      case .value(let value):
        if value == truncation { e1.fulfill() }
      case .error(let error):
        let e = error as NSError
        if (e.domain == "bogus") { e2.fulfill() }
      }
    }

    XCTAssert(stream.requested == Int64(limit))

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
  
  func testReduce()
  {
    let stream = Stream<Int>(queue: dispatch_get_global_queue(qos_class_self(), 0))
    let events = 11

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.reduce(0) { u,i in u+i }
    m.notify {
      result in
      switch result
      {
      case .value(let value):
        if value == (events-1)*events/2 { e1.fulfill() }
      case .error(let error):
        if error is StreamCompleted { e2.fulfill() }
      }
    }

    for i in 0..<events { stream.process(i) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testCoalesce()
  {
    let stream = Stream<Int>(queue: dispatch_get_global_queue(qos_class_self(), 0))
    let events = 10

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let m = stream.map(transform: { i in Double(2*i) }).coalesce()
    m.notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value.count == events, "Coalesced \(value.count) events instead of \(events)")
        let reduced = value.reduce(0, combine: +)
        if reduced == Double((events-1)*events) { e1.fulfill() }
      case .error(let error):
        if error is StreamCompleted { e2.fulfill() }
      }
    }

    for i in 0..<events { stream.process(i) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testSplit1()
  {
    let stream = Stream<Int>()
    let events = 10

    let split = stream.split()
    XCTAssert(stream.requested == 0)

    let e1 = expectationWithDescription("split.0 onValue")
    let e2 = expectationWithDescription("split.0 onError")

    var a0 = [Int]()
    let s0 = split.0.coalesce()
    s0.notify {
      result in
      switch result
      {
      case .value(let value):
        a0 = value
        if value.count == events { e1.fulfill() }
        else { print("a0 has \(a0.count) elements") }
      case .error(let error):
        if error is StreamCompleted { e2.fulfill() }
      }
    }

    let e3 = expectationWithDescription("split.1 onValue")
    let e4 = expectationWithDescription("split.1 onError")

    var a1 = [Int]()
    let s1 = split.1.coalesce()
    s1.onValue {
      value in
      a1 = value
      if value.count == events { e3.fulfill() }
      else { print("a1 has \(a1.count) elements") }
    }
    s1.onCompletion { _ in e4.fulfill() }

    // FIXME: race condition
    // By the time stream.process() is called for the first time,
    // stream.requested should have been updated.
    // This test does not guarantee the update happens on time,
    // though it usually does happen on time. Race condition.
    XCTAssert(s0.requested == 1)
    XCTAssert(s1.requested == 1)
    XCTAssert(split.0.requested == Int64.max)
    XCTAssert(split.1.requested == Int64.max)
    XCTAssert(stream.requested == Int64.max)

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(0.1, handler: nil)

    XCTAssert(a0 == a1)
  }

  func testSplit2()
  {
    let stream = Stream<Int>()
    let events = 10
    let splits = 3

    let e = expectationWithDescription("observation complete")

    let split = stream.split(count: splits)
    XCTAssert(stream.requested == 0)

    let merged = MergeStream<Int>()
    split.forEach(merged.merge)

    merged.countEvents().onValue {
      count in
      if count == splits*events { e.fulfill() }
      else { print(count) }
    }

    // FIXME: race condition (worked around)
    // By the time stream.process() is called for the first time, stream.requested might not have been updated
    dispatch_barrier_sync(merged.queue) {}

    XCTAssert(stream.requested > 0)
    for i in 0..<events { stream.process(i+1) }
    stream.close()
    merged.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testSplit3()
  {
    let stream = Stream<Int>()
    let events = 10

    let e1 = expectationWithDescription("split.0 onValue")

    let split = stream.split()

    split.0.countEvents().onValue {
      count in
      count == events ? e1.fulfill() : XCTFail("split.0 expected \(events) events, got \(count)")
    }

    XCTAssert(split.0.requested == Int64.max)
    XCTAssert(stream.requested == Int64.max)

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let e3 = expectationWithDescription("split.1 onValue")

    XCTAssert(split.1.requested == 0)
    split.1.countEvents().onValue {
      count in
      count == 0 ? e3.fulfill() : XCTFail("split.1 never had a non-zero request")
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
}

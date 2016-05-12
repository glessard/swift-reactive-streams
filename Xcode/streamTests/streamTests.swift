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
        if error is StreamClosed { e2.fulfill() }
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
      if error is StreamClosed { e2.fulfill() }
    }

    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMap1()
  {
    let events = 10
    let stream = Stream<Int>()

    let e2 = expectationWithDescription("observation onError")

    var d = Array<Double>()
    let m = stream.map(transform: { 2.0*Double($0) }).map(transform: { d.append($0) })
    m.onError {
      error in
      guard let t = error as? StreamClosed else { return }
      guard case .ended = t else { return }
      XCTAssert(d.count == events)
      e2.fulfill()
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
        if (error is StreamClosed) { e2.fulfill() }
      }
    }

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
        if error is StreamClosed { e2.fulfill() }
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
        if error is StreamClosed { e2.fulfill() }
      }
    }

    for i in 0..<events { stream.process(i) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testSplit()
  {
    let stream = Stream<Int>()
    let events = 10

    let e1 = expectationWithDescription("observation onValue")
    let e2 = expectationWithDescription("observation onError")

    let split = stream.split()

    var a0 = [Int]()
    split.0.coalesce().notify {
      result in
      switch result
      {
      case .value(let value):
        a0 = value
        if value.count == events { e1.fulfill() }
      case .error(let error):
        if error is StreamClosed { e2.fulfill() }
      }
    }

    for i in 0..<events { stream.process(i+1) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let e3 = expectationWithDescription("observation onValue")
    let e4 = expectationWithDescription("observation onError")

    var a1 = [Int]()
    let s1 = split.1.coalesce()
    s1.onValue {
      value in
      a1 = value
      if value.count == events { e3.fulfill() }
    }
    s1.onEnd { e4.fulfill() }

    waitForExpectationsWithTimeout(1.0, handler: nil)

    XCTAssert(a0 == a1)
  }
}

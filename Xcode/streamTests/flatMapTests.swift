//
//  flatMapTests.swift
//  stream
//
//  Created by Guillaume Lessard on 08/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
@testable import stream

class flatMapTests: XCTestCase
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

  func testFlatMap1()
  {
    let stream = Stream<Int>()
    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap {
      count -> Stream<Double> in
      let s = Stream<Double>()
      XCTFail()
      s.close()
      return s
    }

    m.notify {
      result in
      switch result
      {
      case .value: XCTFail()
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
        else { print(error) }
      }
    }

    stream.close()
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFlatMap2()
  {
    let stream = Stream<Int>()
    let events = 10
    let reps = 5

    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().onValue {
      count in
      if count != reps*events { print(count) }
      XCTAssert(count == reps*events)
      e.fulfill()
    }

    for _ in 0..<reps { stream.process(events) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFlatMap3()
  {
    let stream = Stream<Int>()
    let events = 10

    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap {
      count -> Stream<Double> in
      let s = Stream<Double>()
      s.close()
      return s
    }

    m.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        if value != 0 { print(value) }
        XCTAssert(value == 0)
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
        else { print(error) }
      }
    }

    stream.process(events)
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFlatMap4()
  {
    let stream = Stream<Int>()
    let events = 10

    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        if value != events*events { print(value) }
        XCTAssert(value == events*events)
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
        else { print(error) }
      }
    }

    for _ in (0..<events) { stream.process(events) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFlatMap5()
  {
    let stream = Stream<Int>()
    let events = 10
    let limit = 5

    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap {
      count -> Stream<Double> in
      let s = OnRequestStream().next(count: events).map {
        i throws -> Double in
        if i < limit { return Double(i) }
        else { throw NSError(domain: "bogus", code: i*count, userInfo: nil) }
      }
      return s
    }

    m.notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value < Double(limit), "value of \(value) reported")
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default: XCTFail()
      }
    }

    for i in (1...events) { stream.process(i) }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFlatMap6()
  {
    let stream = Stream<Int>()
    let events = 10
    let limit = 5

    let e = expectationWithDescription("observation ends \(random())")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == 0, "event count of \(value) reported instead of zero")
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default: XCTFail()
      }
    }

    for i in (1...events)
    {
      if i < limit { stream.process(i) }
      else         { stream.process(NSError(domain: "bogus", code: i, userInfo: nil)) }
    }
    stream.close()

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
}

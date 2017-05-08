//
//  flatMapTests.swift
//  stream
//
//  Created by Guillaume Lessard on 08/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import stream

class flatMapTests: XCTestCase
{
  func testFlatMap1()
  {
    let s = EventStream<Int>()
    let e = expectation(description: "observation ends \(arc4random())")

    let m = s.flatMap {
      count -> EventStream<Double> in
      let s = EventStream<Double>()
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

    s.close()
    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap2()
  {
    let stream = PostBox<Int>()
    let events = 10
    let reps = 5

    let e = expectation(description: "observation ends \(arc4random())")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().onValue {
      count in
      if count != reps*events { print(count) }
      XCTAssert(count == reps*events)
      e.fulfill()
    }

    for _ in 0..<reps { stream.post(events) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap3()
  {
    let s = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation ends \(#function)")

    let m = s.flatMap(DispatchQueue.global()) {
      count -> EventStream<Double> in
      let s = EventStream<Double>()
      s.close()
      // The new stream is already closed on return, therefore subscriptions will fail
      return s
    }

    m.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        if value != 0 { print(value) }
        XCTAssert(value == 0)
      case .error(let error as StreamError):
        if case .subscriptionFailed = error { e.fulfill() }
        else { XCTFail() }
      case .error(let error):
        print(error)
        XCTFail()
      }
    }

    s.post(events)
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap4()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation ends \(arc4random())")

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

    for _ in (0..<events) { stream.post(events) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap5()
  {
    let s = PostBox<Int>()
    let events = 10
    let limit = 5

    let e = expectation(description: "observation ends \(arc4random())")

    let m = s.flatMap {
      count -> EventStream<Double> in
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

    for i in (1...events) { s.post(i) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap6()
  {
    let stream = PostBox<Int>()
    let events = 10
    let limit = 5

    let e = expectation(description: "observation ends \(arc4random())")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == 0, "counted \(value) events instead of zero")
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default: XCTFail()
      }
    }

    for i in (1...events).reversed()
    {
      if i < limit { stream.post(i) }
      else         { stream.post(NSError(domain: "bogus", code: i, userInfo: nil)) }
    }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

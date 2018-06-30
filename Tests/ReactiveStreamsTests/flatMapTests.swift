//
//  flatMapTests.swift
//  stream
//
//  Created by Guillaume Lessard on 08/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class flatMapTests: XCTestCase
{
  func testFlatMap1()
  {
    let s = EventStream<Int>()
    let e = expectation(description: "observation ends \(#function)")

    let m = s.flatMap {
      count -> EventStream<Double> in
      let s = EventStream<Double>()
      XCTFail()
      s.close()
      return s
    }

    m.notify {
      event in
      do {
        _ = try event.get()
        XCTFail()
      }
      catch StreamCompleted.normally { e.fulfill() }
      catch { XCTFail() }
    }

    s.close()
    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap2()
  {
    let stream = PostBox<Int>()
    let events = 10
    let reps = 5

    let e = expectation(description: "observation ends \(#function)")

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
      event in
      do {
        let value = try event.get()
        XCTAssert(value == 0)
      }
      catch StreamError.subscriptionFailed { e.fulfill() }
      catch { XCTFail() }
    }

    s.post(events)
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFlatMap4()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation ends \(#function)")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == events*events)
      }
      catch StreamCompleted.normally { e.fulfill() }
      catch { XCTFail() }
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

    let e = expectation(description: "observation ends \(#function)")

    let m = s.flatMap {
      count -> EventStream<Double> in
      let s = OnRequestStream().next(count: events).map {
        i throws -> Double in
        if i < limit { return Double(i) }
        else { throw TestError(i*count) }
      }
      return s
    }

    m.notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value < Double(limit), "value of \(value) reported")
      }
      catch let error as TestError {
        if error.error >= 5 { e.fulfill() }
      }
      catch { XCTFail() }
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

    let e = expectation(description: "observation ends \(#function)")

    let m = stream.flatMap { OnRequestStream().next(count: $0) }

    m.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == 0, "counted \(value) events instead of zero")
      }
      catch let error as TestError {
        if error.error == events { e.fulfill() }
      }
      catch { XCTFail() }
    }

    for i in (1...events).reversed()
    {
      if i < limit { stream.post(i) }
      else         { stream.post(TestError(i)) }
    }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

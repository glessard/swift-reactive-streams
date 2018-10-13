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
      XCTAssertEqual(count, reps*events)
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
        XCTAssertEqual(value, 0)
      }
      catch StreamCompleted.normally { e.fulfill() }
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
        XCTAssertEqual(value, events*events)
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
        XCTAssertLessThan(value, Double(limit), "value of \(value) reported")
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
        XCTAssertEqual(value, 0, "counted \(value) events instead of zero")
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

  func testFlatMap7()
  {
    let stream = PostBox<EventStream<Int>>()
    let events = 10
    let streams = 4

    let e = expectation(description: "observation ends \(#function)")

    let m = stream.flatMap { $0 }

    m.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, events*(streams/2))
      }
      catch StreamCompleted.normally {
        e.fulfill()
      }
      catch { XCTFail() }
    }

    for i in 1..<streams
    {
      let s = OnRequestStream().next(count: events)
      if i%2 == 0 { s.close() }
      stream.post(s)
    }
    stream.close()

    waitForExpectations(timeout: 0.1)
  }

  func testFlatMap8()
  {
    let stream = PostBox<EventStream<Int>>()

    let m = stream.flatMap { $0 }
    m.onValue { [unowned m] in if $0 >= 10 { m.close() } }
    let e = expectation(description: "observation ends \(#function)")
    m.onCompletion { e.fulfill() }

    for i in 1..<10
    {
      stream.post(OnRequestStream().next(count: 5+i))
    }
    stream.close()

    waitForExpectations(timeout: 0.1)
  }
}

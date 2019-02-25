//
//  reduceTests.swift
//  ReactiveStreamsTests
//
//  Created by Guillaume Lessard on 2/25/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class reduceTests: XCTestCase
{
  func testFinal1()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation onValue")

    let d = (0..<events).map { _ in nzRandom() }

    let f = stream.finalValue()
    f.onValue {
      value in
      XCTAssertEqual(value, d.last)
      e.fulfill()
    }

    d.forEach { stream.post($0) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testFinal2()
  {
    let stream = PostBox<Int>()
    let id = nzRandom()

    let e = expectation(description: "observation onValue")

    let f = stream.finalValue(queue: DispatchQueue.global())
    f.notify {
      event in
      do {
        _ = try event.get()
        XCTFail("not expected to get a value when \"final\" stream is closed")
      }
      catch {
        XCTAssertErrorEquals(error, TestError(id))
        e.fulfill()
      }
    }

    stream.post(TestError(id))

    waitForExpectations(timeout: 1.0)
  }

  func testReduce1()
  {
    let stream = PostBox<Int>(queue: DispatchQueue.global(qos: .utility))
    let events = 11

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    let m = stream.reduce(0, +)
    m.notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, (events-1)*events/2)
        e1.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testReduce2()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let m = stream.reduce(queue: DispatchQueue(label: "test"), 0, {
      sum, e throws -> Int in
      guard sum <= events else { throw TestError() }
      return sum+e
    })
    m.notify {
      event in
      do {
        let value = try event.get()
        XCTAssertGreaterThan(value, events)
        e1.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, TestError())
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testReduceEmptyStream()
  {
    let stream = PostBox<Int>()
    let initial = nzRandom()

    let e1 = expectation(description: #function+"1")
    let e2 = expectation(description: #function+"2")

    let m = stream.reduce(initial, { (c: Int, _) in c-1 })
    m.notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, initial)
        e1.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }

    stream.post(Event.streamCompleted)
    waitForExpectations(timeout: 1.0)
  }

  func testCountEvents()
  {
    let queue = DispatchQueue(label: #function, qos: .default)
    let stream = PostBox<Int>(queue: queue)
    let events = 10

    let e1 = expectation(description: #function+"1")
    let m = stream.countEvents(queue: .global(qos: .userInitiated))
    m.onValue { XCTAssertEqual($0, events) }
    m.onCompletion { e1.fulfill() }

    for i in 1..<events { stream.post(i) }
    queue.sync {}

    let e2 = expectation(description: #function+"2")
    let z = stream.countEvents()
    z.onValue { XCTAssertEqual($0, 1) }
    z.onCompletion { e2.fulfill() }

    stream.post(.max)
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testCoalesce()
  {
    let queue = DispatchQueue(label: #function, qos: .default)
    let stream = PostBox<Int>(queue: queue)
    let events = 10

    let e1 = expectation(description: #function+"1")
    let m = stream.coalesce(queue: .global(qos: .userInitiated))
    m.onValue { XCTAssertEqual($0.count, events) }
    m.onCompletion { e1.fulfill() }

    for i in 1..<events { stream.post(i) }

    let e2 = expectation(description: #function+"2")
    let o = stream.coalesce()
    o.onValue { XCTAssertEqual($0.count, 1) }
    o.onCompletion { e2.fulfill() }

    stream.post(.max)
    stream.close()

    waitForExpectations(timeout: 1.0)
  }
}
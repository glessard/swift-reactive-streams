//
//  mapTests.swift
//  ReactiveStreamsTests
//
//  Created by Guillaume Lessard on 2/25/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class mapTests: XCTestCase
{
  func testMap1()
  {
    let events = 10
    let stream = PostBox<Int>()

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    var d = Array<Double>()
    let m = stream.map(transform: { 2.0*Double($0) }).map(transform: { d.append($0) }).finalValue()
    m.onValue {
      XCTAssertFalse(d.isEmpty)
      e1.fulfill()
    }
    m.onCompletion {
      XCTAssertEqual(d.count, events)
      e2.fulfill()
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testMap2()
  {
    let stream = PostBox<Int>()

    let events = 10
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m = stream.map(queue: DispatchQueue.global()) {
      i throws -> Int in
      if i < limit { return i+1 }
      throw TestError(id)
    }
    m.finalValue().onValue {
      v in
      XCTAssertEqual(v, limit)
      e1.fulfill()
    }
    m.onError {
      error in
      XCTAssertErrorEquals(error, TestError(id))
      e2.fulfill()
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testMap3()
  {
    let stream = PostBox<Int>()

    let events = 10
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m1 = stream.map {
      i -> Event<Int> in
      return
        i < limit ?
          Event(value: (i+1)) :
          Event(error: TestError(id))
    }

    let m2 = m1.map(queue: DispatchQueue.global()) { Event(value: $0+1) }

    m2.notify {
      event in
      do {
        let v = try event.get()
        if v == (limit+1) { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, TestError(id))
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }
}

//
//  filterTests.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2/25/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class filterTests: XCTestCase
{
  func testCompactMap()
  {
    let queue = DispatchQueue(label: "compactMap")
    let stream = OnRequestStream(queue: queue, autostart: false)
    let filtered = stream.compactMap(queue, transform: { i -> Int? in ((i%2)==0 ? i : nil) })

    let e = expectation(description: "compactMap complete")
    filtered.next(count: 5).reduce(0,+).onValue {
      reduced in
      XCTAssertEqual(reduced, 20, "reduced to \(reduced) instead of 20")
      e.fulfill()
    }

    stream.start()
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(stream.completed, false)
    stream.close()
  }

  func testCompact1()
  {
    let stream = OnRequestStream(autostart: false)
    let transformed = stream.map(transform: { i -> Int? in ((i%2)==0 ? i : nil) }).next(count: 10)

    let e = expectation(description: #function)
    transformed.compact().countEvents().onValue {
      count in
      XCTAssertEqual(count, 5)
      e.fulfill()
    }

    stream.start()
    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(stream.completed, false)
    stream.close()
  }

  func testCompact2()
  {
    let q1 = DispatchQueue(label: "stream", qos: .utility)
    let stream = PostBox<Int>(queue: q1)

    let q2 = DispatchQueue(label: "map", qos: .background)
    let transformed = stream.map(queue: q2, transform: { ($0%2)==0 ? Optional($0) : nil })

    let q3 = DispatchQueue(label: "compaction", qos: .default)
    let compacted = transformed.compact(queue: q3)

    XCTAssertEqual(stream.requested, 0)
    let e = expectation(description: #function)
    compacted.next(count: 1).onValue {
      i in
      XCTAssertEqual(i, 2)
      e.fulfill()
    }
    XCTAssertEqual(stream.requested, 1)
    XCTAssertEqual(transformed.requested, 1)

    stream.post(1)
    q1.sync {}
    q2.sync {}
    q3.sync {}
    XCTAssertEqual(stream.requested, 1)
    XCTAssertEqual(transformed.requested, 1)

    stream.post(2)
    q1.sync {}
    q2.sync {}
    q3.sync {}
    XCTAssertEqual(stream.requested, 0)
    XCTAssertEqual(transformed.requested, 0)

    waitForExpectations(timeout: 0.1)
  }

  func testFilter1()
  {
    let events = 100
    let divisor = 20

    let stream = OnRequestStream(autostart: false)
    let filtered = stream.next(count: events).filter(predicate: { ($0%divisor)==0 })

    let e = expectation(description: #function)
    filtered.countEvents().onValue {
      count in
      XCTAssertEqual(count, events/divisor, "counted \(count) events instead of \(events/divisor)")
      e.fulfill()
    }
    XCTAssertEqual(stream.requested, Int64(events))

    stream.start()
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(stream.completed, false)
    stream.close()
  }

  func testFilter2()
  {
    let stream = OnRequestStream(autostart: false)

    let filtered = stream.filter(queue: DispatchQueue(label: #function)) { ($0%3)==1 }
    filtered.onValue { if $0 > 99 { stream.close() } }

    let f = expectation(description: #function)
    filtered.onCompletion { f.fulfill() }

    stream.start()
    waitForExpectations(timeout: 1.0)
  }
}

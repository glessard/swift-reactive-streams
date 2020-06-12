//
//  eventTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 6/5/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import ReactiveStreams

class eventTests: XCTestCase
{
  func testGetters() throws
  {
    let value = Event<Int>(value: .max)
    XCTAssertNotNil(value.value)
    XCTAssertNil(value.error)
    XCTAssertEqual(value.isValue, true)
    XCTAssertEqual(value.isError, false)
    XCTAssertEqual(value.completedNormally, false)

    let error = Event<Int>(error: TestError.value(.min))
    XCTAssertNil(error.value)
    XCTAssertNotNil(error.error)
    XCTAssertNotNil(error.result)
    XCTAssertEqual(error.isValue, false)
    XCTAssertEqual(error.isError, true)
    XCTAssertEqual(error.completedNormally, false)

    let final = Event<Int>(error: nil)
    XCTAssertNil(final.value)
    XCTAssertNil(final.error)
    XCTAssertNil(final.result)
    XCTAssertEqual(final.completedNormally, true)
  }

  func testGet() throws
  {
    let value = Event<Int>(value: .max)
    XCTAssertEqual(try value.get(), .max)

    let error = Event<Int>(error: TestError())
    do {
      _ = try error.get()
    }
    catch TestError.value(let e) {
      XCTAssertEqual(e, 0)
    }

    let final = Event<Int>.streamCompleted
    do {
      _ = try final.get()
    }
    catch is StreamCompleted {
      XCTAssert(true)
    }
  }

  func testDescription()
  {
    let i1 = nzRandom()
    let o1 = Event(value: i1)
    let d1 = String(describing: o1)
    XCTAssert(d1.contains(String(describing: i1)))

    let e2 = TestError(nzRandom())
    let o2 = Event<Unicode.Scalar>(error: e2)
    let d2 = String(describing: o2)
    XCTAssert(d2.contains(String(describing: e2)))

    let o3 = Event<Error>.streamCompleted
    let d3 = String(describing: o3)
    XCTAssertEqual(d3, "Stream Completed")
  }

  func testEquals()
  {
    let i1 = nzRandom()
    let i2 = nzRandom()
    let i3 = i1*i2

    let e3 = Event(value: i1*i2)
    XCTAssertEqual(e3, Event(value: i3))
    XCTAssertNotEqual(e3, Event(value: i2))

    var e4 = e3
    e4 = Event(error: TestError(i1))
    XCTAssertNotEqual(e3, e4)
    XCTAssertNotEqual(e4, Event(error: TestError(i2)))

    var e5 = e4
    e5 = Event.streamCompleted
    XCTAssertNotEqual(e5, e3)
    XCTAssertEqual(e5, Event.streamCompleted)
  }

  func testHashable()
  {
    let e1 = Event<Double>.streamCompleted
    let e2 = Event(value: 5.1)
    let e3 = Event<Double>(error: TestError())

    let s: Set = [e1, e2, e3]

    XCTAssertTrue(s.contains(e2))
  }
}

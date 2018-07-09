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
  func testEquals() throws
  {
#if swift (>=4.1)
    let e1 = Event(value: nzRandom())
    let e2 = try Event(value: e1.get())
    XCTAssert(e1 == e2)

    let e3 = try Event<Int>(error: TestError(e1.get()))
    XCTAssert(e1 != e3)
    XCTAssert(e3 != Event(error: TestError(0)))
#endif
  }

  func testGetters() throws
  {
    let v1 = nzRandom()
    let v2 = nzRandom()

    let value = Event<Int>(value: v1)
    let error = Event<Int>(error: TestError(v2))
    let final = Event<Int>.streamCompleted

    do {
      let v = try value.get()
      XCTAssert(v1 == v)

      let _ = try error.get()
    }
    catch let error as TestError {
      XCTAssert(v2 == error.error)
    }

    XCTAssertNotNil(value.value)
    XCTAssertNotNil(error.error)
    XCTAssertNotNil(final.final)

    XCTAssertNil(value.error)
    XCTAssertNil(value.final)
    XCTAssertNil(error.final)
    XCTAssertNil(error.value)

    XCTAssertTrue(value.isValue)
    XCTAssertFalse(error.isValue)

    let v = String(describing: value)
    let e = String(describing: error)
    let f = String(describing: final)
    // print(v, e, f, terminator: "\n")

    XCTAssert(v != e)
    XCTAssert(v != f)
    XCTAssert(e != f)
  }
}

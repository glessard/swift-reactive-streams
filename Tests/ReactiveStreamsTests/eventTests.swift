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
    let error = Event<Int>(error: TestError.value(.min))
    let final = Event<Int>.streamCompleted

    XCTAssertNotNil(value.value)
    XCTAssertNil(value.streamError)
    XCTAssertNil(value.streamCompleted)
    XCTAssertNil(value.error)

    XCTAssertNil(error.value)
    XCTAssertNotNil(error.streamError)
    XCTAssertNil(error.streamCompleted)
    XCTAssertNotNil(error.error)

    XCTAssertNil(final.value)
    XCTAssertNil(final.streamError)
    XCTAssertNotNil(final.streamCompleted)
    XCTAssertNotNil(final.error)
  }
}

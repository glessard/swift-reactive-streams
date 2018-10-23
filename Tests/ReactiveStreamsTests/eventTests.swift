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
    XCTAssertNil(value.streamError)
    XCTAssertNil(value.streamCompleted)
    XCTAssertNil(value.error)

    let error = Event<Int>(error: TestError.value(.min))
    XCTAssertNil(error.value)
    XCTAssertNotNil(error.streamError)
    XCTAssertNil(error.streamCompleted)
    XCTAssertNotNil(error.error)

    let final = Event<Int>.streamCompleted
    XCTAssertNil(final.value)
    XCTAssertNil(final.streamError)
    XCTAssertNotNil(final.streamCompleted)
    XCTAssertNotNil(final.error)

    let tardy = Event<Int>(error: StreamCompleted.lateSubscription)
    XCTAssertNil(tardy.value)
    XCTAssertNotNil(tardy.streamError)
    XCTAssertNotNil(tardy.streamCompleted)
    XCTAssertNotNil(tardy.error)
  }
}

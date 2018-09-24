//
//  File.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import ReactiveStreams
import deferred

class deferredTests: XCTestCase
{
  func testSingleValueStreamWithValue() throws
  {
    let tbd = TBD<Int>()
    let random = nzRandom()
    let stream = SingleValueStream(from: tbd)

    let e1 = expectation(description: "observe value")
    let e2 = expectation(description: "observe completion")

    XCTAssert(stream.requested == 0)
    stream.notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == random)
        e1.fulfill()
      }
      catch StreamCompleted.normally {
        e2.fulfill()
      }
      catch { XCTFail() }
    }
    XCTAssert(stream.requested == 1)

    tbd.determine(value: random)

    waitForExpectations(timeout: 0.1)
  }

  func testSingleValueStreamWithError() throws
  {
    let tbd = TBD<Int>()
    let random = nzRandom()
    let stream = tbd.eventStream

    let e = expectation(description: "observe error")

    XCTAssert(stream.requested == 0)
    stream.notify {
      event in
      do {
        let _ = try event.get()
        XCTFail()
      }
      catch TestError.value(let v) {
        XCTAssert(v == random)
        e.fulfill()
      }
      catch { XCTFail() }
    }
    XCTAssert(stream.requested == 1)

    tbd.determine(error: TestError(random))

    waitForExpectations(timeout: 0.1)
  }

  func testNext() throws
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 5

    let m = stream.skip(count: limit).next()

    XCTAssert(stream.requested == Int64(limit+1))

    for i in 0..<events { stream.post(i) }
    stream.close()

    let value = try m.get()
    XCTAssert(value == limit)
  }
}

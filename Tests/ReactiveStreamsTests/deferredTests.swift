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
    let stream = SingleValueStream(queue: DispatchQueue(label: #function), from: tbd)

    let e1 = expectation(description: "observe value")
    let e2 = expectation(description: "observe completion")

    XCTAssertEqual(stream.requested, 0)
    stream.notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, random)
        e1.fulfill()
      }
      catch StreamCompleted.normally {
        e2.fulfill()
      }
      catch { XCTFail() }
    }
    XCTAssertEqual(stream.requested, 1)

    tbd.determine(value: random)

    waitForExpectations(timeout: 0.1)
  }

  func testSingleValueStreamWithError() throws
  {
    let tbd = TBD<Int>()
    let random = nzRandom()
    let stream = tbd.eventStream

    let e = expectation(description: "observe error")

    XCTAssertEqual(stream.requested, 0)
    stream.notify {
      event in
      do {
        let _ = try event.get()
        XCTFail()
      }
      catch TestError.value(let value) {
        XCTAssertEqual(value, random)
        e.fulfill()
      }
      catch { XCTFail() }
    }
    XCTAssertEqual(stream.requested, 1)

    tbd.determine(error: TestError(random))

    waitForExpectations(timeout: 0.1)
  }

  func testNext() throws
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 5

    let m = stream.skip(count: limit).next()

    XCTAssertEqual(stream.requested, Int64(limit+1))

    for i in 0..<events { stream.post(i) }
    stream.close()

    let value = try m.get()
    XCTAssertEqual(value, limit)
  }

  func testFinalOutcome() throws
  {
    let s1 = OnRequestStream().map(transform: { $0+1 }).next(count: 10)
    let d1 = s1.finalOutcome()
    let f1 = try d1.get()
    XCTAssertEqual(f1, 10)

    let s2 = OnRequestStream().map {
      i throws -> Int in
      guard i < 5 else { throw TestError(i) }
      return i
    }
    let d2 = s2.finalOutcome()
    do {
      _ = try d2.get()
      XCTFail()
    }
    catch TestError.value(let i) {
      XCTAssertEqual(i, 5)
    }

    let s3 = PostBox<()>()
    let d3 = s3.finalOutcome()
    s3.close()
    do {
      _ = try d3.get()
      XCTFail()
    }
    catch DeferredError.canceled(let m) {
      XCTAssertNotEqual(m, "")
    }
  }
}

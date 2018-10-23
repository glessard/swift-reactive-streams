//
//  File.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import Dispatch
import ReactiveStreams
import deferred

class deferredTests: XCTestCase
{
  func testDeferredStreamWithValue() throws
  {
    let tbd = TBD<Int>()
    let random = nzRandom()
    let queue = DispatchQueue(label: #function)
    let stream = DeferredStream(queue: queue, from: tbd)

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
      catch { XCTFail(String(describing: error)) }
    }
    queue.sync {
      XCTAssertEqual(stream.requested, 1)
    }

    tbd.determine(value: random)
    waitForExpectations(timeout: 0.1)
  }

  func testDeferredStreamWithError() throws
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
        XCTFail("stream not expected to produce a value")
      }
      catch TestError.value(let value) {
        XCTAssertEqual(value, random)
        e.fulfill()
      }
      catch { XCTFail(String(describing: error)) }
    }
    XCTAssertEqual(stream.requested, 1)

    tbd.determine(error: TestError(random))
    waitForExpectations(timeout: 0.1)
  }

  func testDeferredStreamAlreadyDetermined() throws
  {
    let random = nzRandom()
    let deferred = Deferred(value: random)
    let stream = deferred.eventStream

    // when `deferred` is already determined, the first stream
    // to subscribe and (make a request) will get the value.
    let e = expectation(description: #function)
    stream.onValue {
      value in
      XCTAssertEqual(value, random)
      e.fulfill()
    }

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
      XCTFail("stream not expected to produce a value")
    }
    catch TestError.value(let i) {
      XCTAssertEqual(i, 5)
    }

    let s3 = PostBox<()>()
    let d3 = s3.finalOutcome()
    s3.close()
    do {
      _ = try d3.get()
      XCTFail("stream not expected to produce a value")
    }
    catch DeferredError.canceled(let m) {
      XCTAssertNotEqual(m, "")
    }
  }
}

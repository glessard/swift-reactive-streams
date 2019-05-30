//
//  streamTests.swift
//  streamTests
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams
import deferred

class postBoxTests: XCTestCase
{
  func testPostNormal()
  {
    let e = expectation(description: #function)
    let stream = PostBox<Int>()

    XCTAssertEqual(stream.requested, 0)

    stream.post(0)
    stream.post(Event(value: 1))
    stream.post(StreamCompleted.normally)

    stream.reduce(0, +).onEvent {
      event in
      do {
        let r = try event.get()
        XCTAssertEqual(r, 1)
      }
      catch StreamCompleted.normally { e.fulfill() }
      catch { XCTFail(String(describing: error)) }
    }

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(stream.requested, .min)
  }

  func testPostAfterCompletion() throws
  {
    let stream = PostBox<Int>()

    let d = stream.finalOutcome()

    stream.post(StreamCompleted.normally)
    stream.post(42)

    do {
      _ = try d.get()
    }
    catch DeferredError.canceled {}
  }

  func testPostDoubleTermination() throws
  {
    let stream = PostBox<Int>()

    let d = stream.finalOutcome()

    stream.post(StreamCompleted.normally)
    stream.post(TestError(42))

    do {
      _ = try d.get()
    }
    catch DeferredError.canceled {}
  }

  func testPostErrorWithoutRequest()
  {
    let e = expectation(description: #function)
    let stream = PostBox<Int>()

    stream.onError {
      error in
      XCTAssert(error is TestError)
      XCTAssertEqual(error as? TestError, TestError(-1))
      e.fulfill()
    }

    XCTAssertEqual(stream.requested, 0)

    stream.post(TestError(-1))

    waitForExpectations(timeout: 1.0)
  }

  func testPostConcurrentProducers() throws
  {
    let producers = 2
    let totalPosts = 10_000

    let s = PostBox<Int>(qos: .userInitiated)
    let c = s.countEvents(qos: .default).finalOutcome()

    DispatchQueue.global(qos: .background).async {
      DispatchQueue.concurrentPerform(iterations: producers) {
        p in
        let segment = totalPosts/producers
        for i in 0..<segment { s.post(p*segment + i) }
      }
      s.close()
    }

    let posted = try c.get()
    XCTAssertEqual(posted, (totalPosts/producers)*producers)
  }

  func testPostDeinitWithPendingEvents() throws
  {
    let s = {
      () -> EventStream<Double> in
      let p = PostBox<Int>()
      XCTAssert(p.isEmpty)
      for i in 0..<10 { p.post(i) }
      XCTAssertFalse(p.isEmpty)
      return p.map(transform: Double.init(_:))
    }()

    s.close()
  }

  func testPerformanceDequeue()
  {
    let iterations = 10_000

#if (!swift(>=4.1) && os(Linux))
    let metrics = XCTestCase.defaultPerformanceMetrics()
#else
    let metrics = XCTestCase.defaultPerformanceMetrics
#endif
    measureMetrics(metrics, automaticallyStartMeasuring: false) {
      let s = PostBox<Int>()
      for i in 0..<iterations { s.post(i) }
      s.close()

      let c = s.countEvents()

      startMeasuring()
      let count = c.finalOutcome().value
      stopMeasuring()

      XCTAssertEqual(count, iterations)
    }
  }

  func testPostBoxSubClass()
  {
    class TestBox: PostBox<Int> {}

    let t = TestBox()
    let c = t.countEvents()

    t.post(1)
    t.close()

    let count = c.finalOutcome().value
    XCTAssertEqual(count, 1)
  }
}

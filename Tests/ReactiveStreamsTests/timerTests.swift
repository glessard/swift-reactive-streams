//
//  timerTests.swift
//  stream
//
//  Created by Guillaume Lessard on 7/3/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class timerTests: XCTestCase
{
  func testTimerCreation()
  {
    let s = TimerStream(interval: 0.01)

    let now = Date()
    let e = expectation(description: "timer creation")
    s.next(count: 1).onValue {
      d in
      if d > now { e.fulfill() }
    }

    s.startTimer()
    waitForExpectations(timeout: 0.1)
    s.close()
  }

  func testUnusedTimer()
  {
    let s = TimerStream(interval: 0.01)
    let n = s.next(count: 10)
    XCTAssertNotEqual(s.state, .streaming)
    n.onCompletion { XCTFail() }

    var t = TimerStream(interval: 0.01).finalValue()
    XCTAssert(!t.completed)
    t = s
  }

  func testTimerTiming()
  {
    let interval = 0.001
    let repeats = 10
    let s = TimerStream(interval: interval)
    let c = s.next(count: repeats).countEvents()
    let e = expectation(description: "timer timing")
    c.onValue { XCTAssertEqual($0, repeats) }
    c.onCompletion { e.fulfill() }

    s.startTimer()
    waitForExpectations(timeout: 0.1)
    let elapsed = Date().timeIntervalSince(s.startTimer())
    XCTAssertGreaterThan(elapsed, interval*Double(repeats-1))
  }
}

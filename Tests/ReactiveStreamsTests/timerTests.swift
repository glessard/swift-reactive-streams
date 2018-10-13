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
    let tolerance = 50*10e-6 // == .microseconds(50)
    let repeats = 10
    let s = TimerStream(interval: interval, tolerance: .microseconds(50))

    var startDate: Date? = nil
    let e = expectation(description: "timer timing")
    s.next(count: repeats).finalValue().onValue {
      endDate in
      guard let startDate = startDate else { return }

      let elapsed = endDate.timeIntervalSince(startDate)
      let minimumElapsed = interval*Double(repeats-1)-tolerance
      XCTAssertGreaterThan(elapsed, minimumElapsed)
      e.fulfill()
    }

    startDate = s.startTimer()
    waitForExpectations(timeout: 0.1)
    XCTAssert(startDate == s.startTimer())
  }
}

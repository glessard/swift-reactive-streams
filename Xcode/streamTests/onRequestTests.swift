//
//  onRequestTests.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
@testable import stream

class onRequestTests: XCTestCase
{
  func testOnRequest1()
  {
    let e = expectation(description: "on-request")

    let o = OnRequestStream(autostart: false)

    o.next(count: 10).reduce(0, +).notify {
      result in
      switch result
      {
      case .value(let value) where value == 45: e.fulfill()
      case .error(_ as StreamCompleted):        break
      default:                                  XCTFail()
      }
    }

    o.start()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testOnRequest2()
  {
    let e = expectation(description: "deinit")
    let f = expectation(description: "completion")
    let g = expectation(description: "data")

    class Test: OnRequestStream
    {
      let e: XCTestExpectation

      init(expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(qos: DispatchQoS.current()))
      }

      deinit
      {
        e.fulfill()
      }
    }

    let t = Test(expectation: e).paused()
    let s = t.next(count: 5).countEvents()
    s.onValue { if $0 == 5 { g.fulfill() } }
    s.onCompletion { _ in f.fulfill() }
    s.onError { _ in XCTFail() }
    t.start()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testOnRequest3()
  {
    let s = OnRequestStream().split()

    let e0 = expectation(description: "first")
    let p0 = s.0.paused()
    p0.next(count: 10).reduce(0, +).notify {
      result in
      switch result
      {
      case .value(let value) where value == 45: e0.fulfill()
      case .error(_ as StreamCompleted):        break
      default:                                  XCTFail()
      }
    }
    p0.start()

    waitForExpectations(timeout: 1.0, handler: nil)

    XCTAssert(s.0.state == .ended)
    XCTAssert(s.1.state == .waiting)

    let e1 = expectation(description: "second")
    let p1 = s.1.paused()
    p1.next(count: 10).reduce(0, +).notify {
      result in
      switch result
      {
      case .value(let value) where value == 145: e1.fulfill()
      case .error(_ as StreamCompleted):         break
      default:                                   XCTFail()
      }
    }
    p1.start()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

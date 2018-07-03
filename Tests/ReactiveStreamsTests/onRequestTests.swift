//
//  onRequestTests.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch 
import ReactiveStreams

class onRequestTests: XCTestCase
{
  func testOnRequest1()
  {
    let e = expectation(description: "on-request")

    let o = OnRequestStream(DispatchQueue.global(qos: .background), autostart: false)

    o.next(count: 10).reduce(0, +).notify {
      event in
      do {
        let value = try event.get()
        if value == 45 { e.fulfill() }
        else { XCTFail() }
      }
      catch is StreamCompleted {}
      catch { XCTFail() }
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
        super.init(validated: ValidatedQueue(label: "test", qos: .utility))
      }

      deinit
      {
        e.fulfill()
      }
    }

    let t = Test(expectation: e).paused()
    let s = t.next(count: 5).countEvents()
    s.onValue { if $0 == 5 { g.fulfill() } }
    s.onCompletion { f.fulfill() }
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
      event in
      do {
        let value = try event.get()
        if value == 45 { e0.fulfill() }
        else { XCTFail() }
      }
      catch is StreamCompleted {}
      catch { XCTFail() }
    }
    p0.start()

    waitForExpectations(timeout: 1.0, handler: nil)
    XCTAssert(s.1.state == .waiting)

    let e1 = expectation(description: "second")
    let p1 = s.1.paused()
    p1.next(count: 10).reduce(0, +).notify {
      event in
      do {
        let value = try event.get()
        if value == 145 { e1.fulfill() }
        else { XCTFail() }
      }
      catch is StreamCompleted {}
      catch { XCTFail() }
    }
    p1.start()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

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

    let o = OnRequestStream(queue: DispatchQueue.global(qos: .background), autostart: false)

    o.next(count: 10).reduce(0, +).notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 45)
        e.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
      }
    }

    o.start()

    waitForExpectations(timeout: 1.0)
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
    let s = t.next(count: 5).map(transform: { if $0 == 4 { throw TestError($0) }}).countEvents()
    s.notify {
      event in
      do {
        let count = try event.get()
        XCTAssertEqual(count, 4)
        g.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, TestError(4))
        t.close()
        f.fulfill()
      }
    }

    t.start()
    waitForExpectations(timeout: 1.0)
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
        XCTAssertEqual(value, 45)
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e0.fulfill()
      }
    }
    p0.start()

    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(s.1.state, .waiting)

    let e1 = expectation(description: "second")
    let p1 = s.1.paused()
    p1.next(count: 10).reduce(0, +).notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 145)
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e1.fulfill()
      }
    }
    p1.start()

    waitForExpectations(timeout: 1.0)
  }
}

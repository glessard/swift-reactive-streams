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

    o.next(count: 10).reduce(0, +).onEvent {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 45)
        e.fulfill()
      }
      catch is StreamCompleted {}
      catch { XCTFail("\(error)") }
    }

    o.start()

    waitForExpectations(timeout: 1.0)
  }

  func testOnRequest2()
  {
    let e = expectation(description: "deinit")
    let f = expectation(description: "completion")
    let g = expectation(description: "data")

    class Test: OnRequestStream<Double>
    {
      let e: XCTestExpectation

      init(expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(label: "test", qos: .utility)) {
          i throws -> Double in
          guard i < 4 else { throw TestError(i) }
          return Double(i)*0.01
        }
      }

      deinit
      {
        e.fulfill()
      }
    }

    let t = Test(expectation: e).paused()
    let s = t.next(count: 5).countEvents()
    s.onEvent {
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
    p0.next(count: 10).reduce(0, +).onEvent {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 45)
      }
      catch is StreamCompleted { e0.fulfill() }
      catch { XCTFail("\(error)") }
    }
    p0.start()

    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(s.1.state, .waiting)

    let e1 = expectation(description: "second")
    let p1 = s.1.paused()
    p1.next(count: 10).reduce(0, +).onEvent {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 145)
      }
      catch is StreamCompleted { e1.fulfill() }
      catch { XCTFail("\(error)") }
    }
    p1.start()

    waitForExpectations(timeout: 1.0)
  }

  func testLifetime()
  {
    class SpyStream: OnRequestStream<Int>
    {
      let e: XCTestExpectation
      init(_ expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(label: "test", qos: .utility), task: { $0 })
      }
      deinit { e.fulfill() }
    }

    let s = SpyStream(expectation(description: #function)).map { 2*$0 }
    s.updateRequest(.max)
    s.close()

    waitForExpectations(timeout: 0.1)
  }
}

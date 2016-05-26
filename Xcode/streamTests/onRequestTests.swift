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
  override func setUp()
  {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }

  override func tearDown()
  {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }

  func testOnRequest1()
  {
    let e = expectationWithDescription("on-request")

    OnRequestStream().next(count: 10).reduce(0, combine: +).onValue { $0 == 45 ? e.fulfill() : XCTFail() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testOnRequest2()
  {
    let e = expectationWithDescription("deinit")

    class Test: OnRequestStream
    {
      let e: XCTestExpectation

      init(expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(qos: qos_class_self(), serial: true))
      }

      deinit
      {
        e.fulfill()
      }
    }

    let s = { Test(expectation: e).next(count: 5).countEvents() }()

    let f = expectationWithDescription("completion")
    s.onCompletion { _ in f.fulfill() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testOnRequest3()
  {
    let s = OnRequestStream().split()

    let e1 = expectationWithDescription("first")
    s.0.next(count: 10).reduce(0, combine: +).onValue {
      total in
      total == 45 ? e1.fulfill() : XCTFail()
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)

    let e2 = expectationWithDescription("second")
    s.1.next(count: 10).reduce(0, combine: +).onValue {
      total in
      total == 145 ? e2.fulfill() : XCTFail()
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
}

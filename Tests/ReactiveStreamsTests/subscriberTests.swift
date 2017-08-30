//
//  subscriberTests.swift
//  stream
//
//  Created by Guillaume Lessard on 4/29/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import XCTest

import ReactiveStreams

class TestSubscriber: Subscriber
{
  var subscription: Subscription!
  let limit = 10
  var received = 0

  let e: XCTestExpectation

  init(expectation: XCTestExpectation)
  {
    e = expectation
  }

  func onSubscribe(_ subscription: Subscription)
  {
    self.subscription = subscription
    subscription.request(1)
  }

  func onValue(_ value: Int)
  {
    received += 1
    if received < limit
    {
      subscription.request(1)
    }
    else
    {
      subscription.cancel()
    }
  }

  func onError(_ error: Error)
  {
    XCTAssert(received <= limit)
    e.fulfill()
  }

  func onCompletion(_ status: StreamCompleted)
  {
    XCTAssert(received <= limit)
    e.fulfill()
  }
}

class subscriberTests: XCTestCase
{
  static let allTests = [
    ("testSubscriber1", testSubscriber1),
    ("testSubscriber2", testSubscriber2),
  ]

  func testSubscriber1()
  {
    let e = expectation(description: #function)

    let stream = OnRequestStream().paused()

    let subscriber = TestSubscriber(expectation: e)

    stream.subscribe(subscriber)
    stream.start()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testSubscriber2()
  {
    let e = expectation(description: #function)

    let stream = PostBox<Int>()

    let subscriber = TestSubscriber(expectation: e)

    stream.subscribe(subscriber)

    stream.post(1)
    stream.post(1)
    stream.post(NSError(domain: "bogus", code: -1, userInfo: nil))

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

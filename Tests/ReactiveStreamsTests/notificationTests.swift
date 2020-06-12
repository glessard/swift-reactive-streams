//
//  notificationTests.swift
//  ReactiveStreamsTests
//
//  Created by Guillaume Lessard on 2/25/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class notifierTests: XCTestCase
{
  func testOnEvent1()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: "onEvent: values")
    var notifier = StreamNotifier(stream, onEvent: {
      event in
      do {
        let value = try event.get()
        if value == events { e1.fulfill() }
      }
      catch is StreamCompleted {}
      catch { XCTFail("\(error)") }
    })

    for i in 1...events { stream.post(i) }
    waitForExpectations(timeout: 1.0)
    notifier.close()

    let e2 = expectation(description: "onEvent: completion")
    notifier = StreamNotifier(stream, onEvent: {
      event in
      XCTAssert(event.completedNormally)
      e2.fulfill()
    })
    notifier.close()
    waitForExpectations(timeout: 1.0)

    XCTAssert(stream.isEmpty)
    stream.close()
    let e3 = expectation(description: "onEvent: error")
    notifier = StreamNotifier(stream, onEvent: {
      event in
      XCTAssert(event.completedNormally)
      e3.fulfill()
    })

    waitForExpectations(timeout: 1.0)
  }

  func testOnEvent2()
  {
    let stream = OnRequestStream()

    let e = expectation(description: #function)
    let notifier = StreamNotifier(stream, onEvent: {
      subscription, event in
      if let c = event.value
      {
        if c < 10
        { subscription.request(1) }
        else
        { subscription.cancel() }
      }
      else
      {
        e.fulfill()
      }
    })
    notifier.request(1)

    waitForExpectations(timeout: 1.0)
    _ = notifier
  }

  func testOnValue1()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: #function)
    let notifier = StreamNotifier(stream, queue: .global()) {
      (v: Int) in
      if v == events { e1.fulfill() }
    }

    for i in 1...events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    stream.onValue() { _ in XCTFail("Shouldn't receive any values after the stream has been closed") }
    _ = notifier
  }

  func testOnValue2()
  {
    let stream = OnRequestStream()

    let e = expectation(description: #function)
    let notifier = StreamNotifier(stream, onValue: {
      subscription, value in
      if value < 10
      {
        subscription.request(1)
      }
      else
      {
        subscription.cancel()
        e.fulfill()
      }
    })
    notifier.request(1)

    waitForExpectations(timeout: 1.0)
    _ = notifier
  }

  func testOnError()
  {
    let e2 = expectation(description: #function)
    let s = PostBox<Int>()

    let notifier = StreamNotifier(s, onError: {
      error in
      XCTAssertErrorEquals(error, TestError(42))
      e2.fulfill()
    })

    s.post(1)
    s.post(TestError(42))
    s.updateRequest(1)

    waitForExpectations(timeout: 1.0)
    _ = notifier
  }

  func testOnComplete()
  {
    let s1 = PostBox<Int>()
    s1.onCompletion { XCTFail("stream not expected to complete normally") }
    s1.post(TestError(-1))

    let e2 = expectation(description: "observation onCompletion")
    let s2 = EventStream<Int>()
    let n2 = StreamNotifier(s2, onCompletion: { e2.fulfill() })
    s2.close()

    waitForExpectations(timeout: 1.0)
    _ = n2
  }
}

class notificationTests: XCTestCase
{
  func testOnEvent()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")
    stream.onEvent(queue: .global()) {
      event in
      do {
        let value = try event.get()
        if value == events { e1.fulfill() }
      }
      catch is StreamCompleted { e2.fulfill() }
      catch { XCTFail("\(error)") }
    }

    for i in 1...events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    let e3 = expectation(description: #function)
    stream.onEvent {
      event in
      do {
        _ = try event.get()
        XCTFail("stream not expected to produce a value")
      }
      catch is StreamCompleted { e3.fulfill() }
      catch { XCTFail("\(error)") }
    }

    waitForExpectations(timeout: 1.0)
  }

  func testOnValue()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: #function)
    stream.onValue(queue: .global()) {
      v in
      if v == events { e1.fulfill() }
    }

    for i in 1...events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    stream.onValue() { _ in XCTFail("Shouldn't receive any values after the stream has been closed") }
  }

  func testOnError()
  {
    let e2 = expectation(description: #function)
    let s = PostBox<Int>()

    s.onError {
      error in
      XCTAssertErrorEquals(error, TestError(42))
      e2.fulfill()
    }

    s.post(1)
    s.post(TestError(42))
    s.updateRequest(1)

    waitForExpectations(timeout: 1.0)
  }

  func testOnComplete()
  {
    let s1 = PostBox<Int>()
    s1.onCompletion { XCTFail("stream not expected to complete normally") }

    s1.post(TestError(-1))

    let e2 = expectation(description: "observation onCompletion")
    let s2 = EventStream<Int>()
    s2.onCompletion { e2.fulfill() }
    s2.close()

    waitForExpectations(timeout: 1.0)
  }
}

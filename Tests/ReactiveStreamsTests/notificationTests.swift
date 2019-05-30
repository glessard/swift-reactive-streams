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
  func testNotify()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")
    var notifier = StreamNotifier(stream, onEvent: {
      event in
      do {
        let value = try event.get()
        if value == events { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    })

    for i in 1...events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    let e3 = expectation(description: #function)
    notifier = StreamNotifier(stream, onEvent: {
      event in
      XCTAssertErrorEquals(event.error, StreamCompleted.lateSubscription)
      e3.fulfill()
    })

    waitForExpectations(timeout: 1.0)
    _ = notifier
  }

  func testOnValue()
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
  func testNotify()
  {
    let events = 10
    let queue = DispatchQueue(label: #function, qos: .userInitiated)
    let stream = PostBox<Int>(queue: queue)

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")
    stream.notify(queue: .global()) {
      event in
      do {
        let value = try event.get()
        if value == events { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }

    for i in 1...events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    let e3 = expectation(description: #function)
    stream.notify() {
      event in
      do {
        _ = try event.get()
        XCTFail("stream not expected to produce a value")
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.lateSubscription)
        e3.fulfill()
      }
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

//
//  File.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import Dispatch
import ReactiveStreams
import deferred

public class SingleValueSubscriberTests: XCTestCase
{
  func makeTestSubscriber(stream: EventStream<Int>, queue: DispatchQueue) -> SingleValueSubscriber<Int>
  {
    return SingleValueSubscriber<Int>(queue: queue) {
      resolver in
      var sub: Subscription? = nil
      stream.subscribe(
        subscriptionHandler: { sub = $0 },
        notificationHandler: { resolver.resolve($0) }
      )
      return sub.unsafelyUnwrapped
    }
  }

  func testSingleValueSubscriberWithValue() throws
  {
    let queue = DispatchQueue(label: #function, qos: .utility)
    let stream = PostBox<Int>(queue: queue)
    let subscriber = makeTestSubscriber(stream: stream, queue: queue)

    let r = nzRandom()
    stream.post(r)
    XCTAssertNil(subscriber.peek())

    subscriber.request(1)
    stream.post(0)
    XCTAssertEqual(subscriber.value, r)

    stream.close()
  }

  func testSingleValueSubscriberWithError() throws
  {
    let queue = DispatchQueue(label: #function, qos: .utility)
    let stream = PostBox<Int>(queue: queue)
    let subscriber = makeTestSubscriber(stream: stream, queue: queue)

    XCTAssertNil(subscriber.peek())

    let r = nzRandom()
    stream.post(TestError(r))
    XCTAssertEqual(subscriber.error as? TestError, TestError(r))
  }

  func testSingleValueSubscriberCancelled() throws
  {
    let queue = DispatchQueue(label: #function, qos: .utility)
    let stream = PostBox<Int>()
    let subscriber = makeTestSubscriber(stream: stream, queue: queue)

    subscriber.requestAll()
    XCTAssertNil(subscriber.peek())
    XCTAssert(subscriber.cancel())

    stream.post(1)

    do {
      let i = try subscriber.get()
      XCTFail("\(i) exists when it should not")
    }
    catch DeferredError.canceled("") {}

    stream.close()
  }
}

class DeferredOperationsTests: XCTestCase
{
  func testNext() throws
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = nzRandom() % events

    let m = stream.skip(count: limit).next()

    XCTAssertEqual(stream.requested, Int64(limit+1))

    for i in 0..<events { stream.post(i) }
    stream.close()

    let value = try m.get()
    XCTAssertEqual(value, limit)
  }

  func testFinalOutcome() throws
  {
    let s1 = OnRequestStream().map(transform: { $0+1 }).next(count: 10)
    let d1 = s1.finalOutcome(queue: DispatchQueue.global(qos: .background))
    let f1 = try d1.get()
    XCTAssertEqual(f1, 10)

    let s2 = OnRequestStream().map {
      i throws -> Int in
      guard i < 5 else { throw TestError(i) }
      return i
    }
    let d2 = s2.finalOutcome(qos: .background)
    do {
      _ = try d2.get()
      XCTFail("stream not expected to produce a value")
    }
    catch TestError(5) {}

    let s3 = PostBox<()>()
    let d3 = s3.finalOutcome()
    s3.close()
    do {
      _ = try d3.get()
      XCTFail("stream not expected to produce a value")
    }
    catch DeferredError.canceled(let m) {
      XCTAssertNotEqual(m, "")
    }
  }
}

class DeferredStreamTests: XCTestCase
{
  func testDeferredStreamWithValue() throws
  {
    let (resolver, tbd) = TBD<Int>.CreatePair()
    let random = nzRandom()
    let queue = DispatchQueue(label: #function)
    let stream = DeferredStream(queue: queue, from: tbd)

    let e1 = expectation(description: "observe value")
    let e2 = expectation(description: "observe completion")

    XCTAssertEqual(stream.requested, 0)
    stream.notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, random)
        e1.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }
    queue.sync {
      XCTAssertEqual(stream.requested, 1)
    }

    resolver.resolve(value: random)
    waitForExpectations(timeout: 1.0)
  }

  func testDeferredStreamWithError() throws
  {
    let (resolver, tbd) = TBD<Int>.CreatePair()
    let random = nzRandom()
    let stream = tbd.eventStream

    let e = expectation(description: "observe error")

    XCTAssertEqual(stream.requested, 0)
    stream.notify {
      event in
      do {
        let _ = try event.get()
        XCTFail("stream not expected to produce a value")
      }
      catch {
        XCTAssertErrorEquals(error, TestError(random))
        e.fulfill()
      }
    }
    XCTAssertEqual(stream.requested, 1)

    resolver.resolve(error: TestError(random))
    waitForExpectations(timeout: 1.0)
  }

  func testDeferredStreamAlreadyDetermined() throws
  {
    let random = nzRandom()
    let deferred = Deferred(value: random)
    let stream = deferred.eventStream

    // when `deferred` is already determined, the first stream
    // to subscribe and (make a request) will get the value.
    let e1 = expectation(description: #function+"-1")
    stream.onValue {
      value in
      XCTAssertEqual(value, random)
      e1.fulfill()
    }

    let flattener = PostBox<EventStream<Int>>()
    let e2 = expectation(description: #function+"-2")
    flattener.flatMap(transform: {$0}).countEvents().onValue {
      i in
      XCTAssertEqual(i, 0)
      e2.fulfill()
    }
    // when `deferred` is already determined, any stream
    // subscribing after the first one will not receive the value.
    flattener.post(stream)
    flattener.close()

    waitForExpectations(timeout: 1.0)
  }
}

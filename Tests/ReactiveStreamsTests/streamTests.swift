//
//  streamTests.swift
//  streamTests
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class streamTests: XCTestCase
{
  func testLifetime1()
  {
    class SpyStream: EventStream<Int>
    {
      let e: XCTestExpectation

      init(_ expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(label: "test", qos: .utility))
      }

      deinit
      {
        e.fulfill()
      }
    }

    let s = SpyStream(expectation(description: "deletion")).finalValue()
    s.close()

    waitForExpectations(timeout: 1.0)
  }

  func testLifetime2()
  {
    class SpyStream: EventStream<Int>
    {
      let e: XCTestExpectation

      init(_ expectation: XCTestExpectation)
      {
        e = expectation
        super.init(validated: ValidatedQueue(label: "test", qos: .utility))
      }

      deinit
      {
        e.fulfill()
      }
    }

    let p = UnsafeMutablePointer<EventStream<Int>>.allocate(capacity: 1)
    p.initialize(to: SpyStream(expectation(description: "deletion")).finalValue())
    p.deinitialize(count: 1)

    waitForExpectations(timeout: 1.0)
    p.deallocate()
  }

  func testLifetime3()
  {
    // is there less messy way to do this test?

    class SpyStream: EventStream<Int>
    {
      override init(validated queue: ValidatedQueue)
      {
        super.init(validated: queue)
      }

      deinit
      {
        XCTFail("this stream should leak")
      }
    }

    let p = UnsafeMutablePointer<EventStream<Int>>.allocate(capacity: 1)
    p.initialize(to: SpyStream().finalValue())
    // the SpyStream should leak because one of its observers is kept alive by the pointer
  }

  func testRequested()
  {
    let queue = DispatchQueue(label: #function, qos: .utility)

    let stream = OnRequestStream(queue: queue)
    XCTAssertEqual(stream.requested, 0)
    let final = stream.finalOutcome()
    XCTAssertEqual(stream.requested, .max)

    let e = expectation(description: #function + "-1")
    final.onError(queue: queue) { _ in e.fulfill() }
    final.cancel()
    waitForExpectations(timeout: 1.0)

    let many = stream.next(queue: queue, count: 10_000)
    XCTAssertNotEqual(stream.requested, .max)
    XCTAssertEqual(stream.requested, 0)

    let manyth = many.finalOutcome(queue: queue)
    XCTAssertLessThanOrEqual(stream.requested, 10_000)
    XCTAssertGreaterThan(stream.requested, 0)

    let f = expectation(description: #function + "-2")
    manyth.notify { _ in f.fulfill() }
    many.close()
    waitForExpectations(timeout: 1.0)

    let next = stream.next(queue: queue, count: 10)
    XCTAssertLessThan(stream.requested, 10_000)
    XCTAssertEqual(stream.requested, 0)
    next.close()
  }

  func testRequestedReset()
  {
    let queue = DispatchQueue(label: #function, qos: .utility)

    var subscription: Subscription? = nil
    let stream = OnRequestStream(queue: queue)
    let e = expectation(description: #function)
    stream.subscribe(
      subscriber: queue,
      subscriptionHandler: { subscription = $0 },
      notificationHandler: {
        (subscriber, subscription, event) in
        subscription.requestNone()
        e.fulfill()
      }
    )

    subscription!.request(100)
    waitForExpectations(timeout: 1.0)
  }

  class SelfTerminatingPostBox<Value>: PostBox<Value>
  {
    override func lastSubscriptionWasCanceled()
    {
      super.lastSubscriptionWasCanceled()
      close()
    }
  }

  func testLastSubscriber()
  {
    let stream = SelfTerminatingPostBox<Int>()
    stream.post(1)

    var e = expectation(description: #function + "-1")
    var s: Subscription?
    stream.subscribe(
      subscriptionHandler: {
        subscription in
        s = subscription
        subscription.request(1)
      },
      notificationHandler: {
        XCTAssert($0 === s)
        if $1.isValue { s?.cancel() }
        else { e.fulfill() }
      }
    )
    waitForExpectations(timeout: 1.0)

    e = expectation(description: #function + "-2")
    stream.finalValue().onError {
      XCTAssertErrorEquals($0, StreamCompleted.lateSubscription)
      e.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testStreamState()
  {
    let s = PostBox<Int>()

    XCTAssertEqual(s.state, .waiting)
    XCTAssertEqual(String(describing: s.state), "EventStream waiting to begin processing events")

    let n = s.next(count: 2)
    n.onEvent {
      event in
    }

    s.post(0)
    XCTAssertEqual(s.state, .streaming)
    XCTAssertEqual(String(describing: s.state), "EventStream active")

    let e2 = expectation(description: "second value")
    let n2 = n.next(count: 1)
    n2.onCompletion { e2.fulfill() }

    s.post(0)
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(s.state, .waiting)
    XCTAssertEqual(String(describing: s.state), "EventStream waiting to begin processing events")
    XCTAssertEqual(n.state, .ended)
    XCTAssertEqual(String(describing: n.state), "EventStream has completed")
  }

  func testSkipN()
  {
    let stream = PostBox<Int>()
    let count = 5

    let e = expectation(description: "observation onCompletion")

    let m = stream.skip(count: count)
    XCTAssertEqual(stream.requested, Int64(count))

    let n = m.next(count: count).skip(queue: DispatchQueue.global(), count: count)
    XCTAssertEqual(stream.requested, Int64(2*count))

    n.onEvent {
      event in
      do {
        _ = try event.get()
        XCTFail("unreachable function")
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e.fulfill()
      }
    }

    for i in 0...2*count { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testNextN()
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let m = stream.next(queue: DispatchQueue.global(), count: limit)
    m.onEvent {
      event in
      do {
        let value = try event.get()
        if value == limit { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }

    XCTAssertEqual(stream.requested, Int64(limit))

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testNextTruncated()
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 50
    let truncation = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m = stream.next(count: limit)
    let t = m.map {
      i throws -> Int in
      if i <= truncation { return i }
      throw TestError(id)
    }
    t.onEvent {
      event in
      do {
        let value = try event.get()
        if value == truncation { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, TestError(id))
        e2.fulfill()
      }
    }

    XCTAssertEqual(stream.requested, Int64(limit))

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testSplit0()
  {
    let stream = PostBox<Int>()
    let split = stream.split(count: 0)
    XCTAssert(split.isEmpty)
    stream.close()
  }

  func testSplit1()
  {
    let stream = PostBox<Int>()
    let events = 10

    let split = stream.split()
    XCTAssertEqual(stream.requested, 0)

    let e1 = expectation(description: "split.0 onValue")
    let e2 = expectation(description: "split.0 onError")

    var a0 = [Int]()
    split.0.coalesce().onEvent {
      event in
      do {
        let value = try event.get()
        a0 = value
        XCTAssertEqual(value.count, events)
        e1.fulfill()
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }
    XCTAssertEqual(split.0.requested, .max)
    XCTAssertEqual(split.1.requested, 0)
    XCTAssertEqual(stream.requested, .max, "stream.requested should have been updated synchronously")

    let e3 = expectation(description: "split.1 onValue")
    let e4 = expectation(description: "split.1 onError")

    var a1 = [Int]()
    let s1 = split.1.coalesce()
    s1.onValue {
      value in
      a1 = value
      XCTAssertEqual(value.count, events)
      e3.fulfill()
    }
    s1.onCompletion { e4.fulfill() }
    XCTAssertEqual(split.1.requested, .max)

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(a0, a1)
  }

  func testSplit2()
  {
    let stream = PostBox<Int>()
    let events = 10
    let splits = 3

    let e = expectation(description: "observation complete")
    let f = expectation(description: "value observed")

    let split = stream.split(count: splits)
    XCTAssertEqual(stream.requested, 0)

    let merged = EventStream.merge(streams: split)

    merged.countEvents().onValue { XCTAssertEqual($0, splits*events); f.fulfill() }
    stream.onCompletion { e.fulfill() }

    XCTAssertEqual(stream.requested, .max)
    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
    merged.close()
  }

  func testSplit3()
  {
    let stream = PostBox<Int>()
    let events = 10

    let split = stream.split()

    XCTAssertEqual(split.0.requested, 0)
    XCTAssertEqual(stream.requested, 0)

    split.0.countEvents().onValue { XCTAssertEqual($0, events) }
    let e0 = expectation(description: "split.0 onCompletion")
    split.0.onCompletion { e0.fulfill() }
    let e1 = expectation(description: "split.1 onCompletion")
    split.1.onCompletion { e1.fulfill() }

    XCTAssertEqual(stream.requested, .max)
    XCTAssertEqual(split.0.requested, .max)
    XCTAssertEqual(split.1.requested, 0)

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(stream.requested, .min)
    XCTAssertEqual(split.0.requested, .min)
    XCTAssertEqual(split.1.requested, .min)

    let e2 = expectation(description: "split.1 onError")
    split.1.onError {
      error in
      XCTAssertErrorEquals(error, StreamCompleted.lateSubscription)
      e2.fulfill()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testSplit4()
  {
    let stream = PostBox<Int>()
    let split = stream.map(transform: {$0+1}).split()
    let events = 10

    let e1 = expectation(description: "\(events) events")
    let e2 = expectation(description: "1 event")

    split.0.countEvents().onValue {
      XCTAssertEqual($0, events); e1.fulfill()
    }

    let sem = DispatchSemaphore(value: 0)
    split.1.onEvent {
      event in
      do {
        let value = try event.get()
        if value == 1 { sem.signal() }
      }
      catch {
        XCTAssertErrorEquals(error, StreamCompleted.normally)
        e2.fulfill()
      }
    }

    stream.post(0)
    _ = sem.wait(timeout: DispatchTime.now() + 1)
    split.1.close()
    (1..<events).forEach { stream.post($0) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testSplit5()
  {
    let stream = PostBox<Int>()
    let split = stream.next(count: 2).split()

    split.0.next(count: 3).onValue { _ in }

    XCTAssertEqual(stream.requested, 2)
    XCTAssertEqual(split.0.requested, 3)
    XCTAssertEqual(split.1.requested, 0)

    stream.post(0)
    let ne = expectation(description: "second value")
    stream.next(count: 1).onValue { _ in ne.fulfill() }
    stream.post(1)
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(stream.requested, 0)

    split.1.next(count: 5).onEvent { _ in }
    XCTAssertEqual(stream.requested, 0)
  }

  func testPaused1()
  {
    let postbox = PostBox<Int>()
    let stream = postbox.paused()
    XCTAssertEqual(stream.isPaused, true)
    stream.start()
    XCTAssertEqual(stream.isPaused, false)
  }

  func testPaused2()
  {
    let postbox = PostBox<Int>()
    let stream = postbox.paused()

    let e1 = expectation(description: "count events")
    let e2 = expectation(description: "coalesce events")

    stream.countEvents().onValue {
      XCTAssertEqual($0, 1); e1.fulfill()
    }
    stream.coalesce().onValue {
      XCTAssertEqual($0.count, 1); e2.fulfill()
    }

    stream.start()
    postbox.post(1)
    postbox.close()

    waitForExpectations(timeout: 1.0)
  }

  func testPaused3() throws
  {
    let stream = PostBox<DispatchSemaphore>()
    let paused = stream.paused()

    func postAndWait()
    {
      let s = DispatchSemaphore(value: 0)
      stream.post(s)
      s.wait()
    }

    XCTAssertEqual(stream.requested, 0)
    XCTAssertEqual(paused.requested, 0)

    let signaler = stream.next(count: 5)
    signaler.onValue() { $0.signal() }

    postAndWait()

    XCTAssertEqual(stream.requested, 4)
    XCTAssertEqual(paused.requested, 0)

    paused.next(count: 10).onValue() { _ in }
    postAndWait()

    XCTAssertEqual(stream.requested, 3)
    XCTAssertEqual(paused.requested, 0)

    paused.start()

    XCTAssertEqual(paused.requested, 10)
    XCTAssertEqual(stream.requested, 10)

    paused.countEvents().onValue(task: { _ in })
    postAndWait()

    XCTAssertEqual(stream.requested, Int64.max, "stream.requested at \(#line)")
    paused.close()
  }
}

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
#if swift(>=4.1)
    p.deallocate()
#else
    p.deallocate(capacity: 1)
#endif
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

  func testLifetime4()
  {
    let stream = PostBox<Int>()

    var f = stream.finalValue()

    stream.post(1)

    let e = expectation(description: "completion")
    f = stream.map { i throws in i }
    f.onCompletion { e.fulfill() }

    stream.post(2)
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testNotify()
  {
    let events = 10
    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")
    let stream = PostBox<Int>()

    stream.notify(queue: DispatchQueue.global()) {
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

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testPost()
  {
    let e1 = expectation(description: "closed")
    let stream = PostBox<Int>()

    stream.onCompletion { e1.fulfill() }

    stream.post(0)
    stream.post(Event(value: 1))
    stream.post(StreamCompleted.normally)

    waitForExpectations(timeout: 1.0)

    stream.post(Int.max)
    stream.post(Event(value: Int.min))
    stream.post(TestError(-1))
  }

  func testStreamState()
  {
    let s = PostBox<Int>()

    XCTAssertEqual(s.state, .waiting)
    XCTAssertEqual(String(describing: s.state), "EventStream waiting to begin processing events")

    let n = s.next(count: 2)
    n.notify {
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

  func testOnValue()
  {
    let events = 10
    let e1 = expectation(description: "observation onValue")
    let stream = PostBox<Int>()

    stream.onValue(queue: DispatchQueue.global()) {
      v in
      if v == events { e1.fulfill() }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testOnError()
  {
    let e2 = expectation(description: "observation onError")
    let s = PostBox<Int>()

    s.onError {
      error in
      if let e = error as? StreamCompleted, e == .normally { XCTFail(String(describing: e)) }
      e2.fulfill()
    }

    s.post(1)
    s.post(TestError(42))

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

  func testMap1()
  {
    let events = 10
    let stream = PostBox<Int>()

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    var d = Array<Double>()
    let m = stream.map(transform: { 2.0*Double($0) }).map(transform: { d.append($0) }).finalValue()
    m.onValue {
      XCTAssertFalse(d.isEmpty)
      e1.fulfill()
    }
    m.onCompletion {
      XCTAssertEqual(d.count, events)
      e2.fulfill()
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testMap2()
  {
    let stream = PostBox<Int>()

    let events = 10
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m = stream.map(queue: DispatchQueue.global()) {
      i throws -> Int in
      if i < limit { return i+1 }
      throw TestError(id)
    }
    m.finalValue().onValue {
      v in
      XCTAssertEqual(v, limit)
      e1.fulfill()
    }
    m.onError {
      error in
      XCTAssertErrorEquals(error, TestError(id))
      e2.fulfill()
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
  }

  func testMap3()
  {
    let stream = PostBox<Int>()

    let events = 10
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m1 = stream.map {
      i -> Event<Int> in
      return
        i < limit ?
          Event(value: (i+1)) :
          Event(error: TestError(id))
    }

    let m2 = m1.map(queue: DispatchQueue.global()) { Event(value: $0+1) }

    m2.notify {
      event in
      do {
        let v = try event.get()
        if v == (limit+1) { e1.fulfill() }
      }
      catch {
        XCTAssertErrorEquals(error, TestError(id))
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0)
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

    n.notify {
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
    m.notify {
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
    t.notify {
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
    split.0.coalesce().notify {
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
    split.1.notify {
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

    split.1.next(count: 5).notify { _ in }
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

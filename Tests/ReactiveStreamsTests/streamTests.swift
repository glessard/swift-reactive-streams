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
  static let allTests = [
    ("testLifetime1", testLifetime1),
    ("testLifetime2", testLifetime2),
    ("testLifetime3", testLifetime3),
    ("testLifetime4", testLifetime4),
    ("testNotify", testNotify),
    ("testPost", testPost),
    ("testOnValue", testOnValue),
    ("testOnError", testOnError),
    ("testOnComplete", testOnComplete),
    ("testMap1", testMap1),
    ("testMap2", testMap2),
    ("testMap3", testMap3),
    ("testNextN", testNextN),
    ("testNextTruncated", testNextTruncated),
    ("testFinal1", testFinal1),
    ("testFinal2", testFinal2),
    ("testFinal3", testFinal3),
    ("testReduce1", testReduce1),
    ("testReduce2", testReduce2),
    ("testCountEvents", testCountEvents),
    ("testCoalesce", testCoalesce),
    ("testSplit0", testSplit0),
    ("testSplit1", testSplit1),
    ("testSplit2", testSplit2),
    ("testSplit3", testSplit3),
    ("testSplit4", testSplit4),
  ].sorted(by: {$0.0 < $1.0})

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

    waitForExpectations(timeout: 1.0, handler: nil)
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
    p.deinitialize()

    waitForExpectations(timeout: 1.0, handler: nil)
    p.deallocate(capacity: 1)
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
    f.onCompletion { _ in e.fulfill() }

    stream.post(2)
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testNotify()
  {
    let events = 10
    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")
    let stream = PostBox<Int>()

    stream.notify(DispatchQueue.global()) {
      result in
      do {
        let value = try result.getValue()
        if value == events { e1.fulfill() }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testPost()
  {
    let e1 = expectation(description: "closed")
    let stream = PostBox<Int>()

    stream.onCompletion { _ in e1.fulfill() }

    stream.post(0)
    stream.post(Result.value(1))
    stream.post(StreamCompleted.normally)

    waitForExpectations(timeout: 1.0, handler: nil)

    stream.post(Int.max)
    stream.post(Result.value(Int.min))
    stream.post(TestError(-1))
  }

  func testOnValue()
  {
    let events = 10
    let e1 = expectation(description: "observation onValue")
    let stream = PostBox<Int>()

    stream.onValue(DispatchQueue.global()) {
      v in
      if v == events { e1.fulfill() }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testOnError()
  {
    let e2 = expectation(description: "observation onError")
    let s = PostBox<Int>()

    s.onError {
      error in
      if error is StreamCompleted { XCTFail() }
      else { e2.fulfill() }
    }

    s.post(1)
    s.post(StreamError.subscriptionFailed)

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testOnComplete()
  {
    let s1 = PostBox<Int>()
    s1.onCompletion {
      _ in XCTFail()
    }

    s1.post(TestError(-1))

    let e2 = expectation(description: "observation onCompletion")
    let s2 = EventStream<Int>()
    s2.onCompletion {
      _ in e2.fulfill()
    }
    s2.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMap1()
  {
    let events = 10
    let stream = PostBox<Int>()

    let e2 = expectation(description: "observation onError")

    var d = Array<Double>()
    let m = stream.map(transform: { 2.0*Double($0) }).map(transform: { d.append($0) }).finalValue()
    m.onCompletion {
      completed in
      if case .normally = completed
      {
        XCTAssert(d.count == events)
        e2.fulfill()
      }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
    // print(d)
  }

  func testMap2()
  {
    let stream = PostBox<Int>()

    let events = 10
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let id = nzRandom()
    let m = stream.map(DispatchQueue.global()) {
      i throws -> Int in
      if i < limit { return i+1 }
      throw TestError(id)
    }
    m.onValue {
      v in
      if v == limit { e1.fulfill() }
    }
    m.onError {
      error in
      if let error = error as? TestError, error == TestError(id)
      { e2.fulfill() }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
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
      i -> Result<Int> in
      return
        i < limit ?
          Result.value((i+1)) :
          Result.error(TestError(id))
    }

    let m2 = m1.map(DispatchQueue.global()) { Result.value($0+1) }

    m2.onValue {
      v in
      if v == (limit+1) { e1.fulfill() }
    }
    m2.onError {
      error in
      if let error = error as? TestError, error == TestError(id)
      { e2.fulfill() }
    }

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testNextN()
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 5

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let m = stream.next(DispatchQueue.global(), count: limit)
    m.notify {
      result in
      do {
        let value = try result.getValue()
        if value == limit { e1.fulfill() }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }

    XCTAssert(stream.requested == Int64(limit))

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
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
      result in
      do {
        let value = try result.getValue()
        if value == truncation { e1.fulfill() }
      }
      catch let error as TestError {
        if error.error == id { e2.fulfill() }
      }
      catch { XCTFail() }
    }

    XCTAssert(stream.requested == Int64(limit))

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFinal1()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation onValue")

    let d = (0..<events).map { _ in nzRandom() }

    let f = stream.finalValue()
    f.onValue {
      value in
      if value == d.last { e.fulfill() }
    }

    d.forEach { stream.post($0) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testFinal2()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation onValue")

    let d = (0..<events).map { _ in nzRandom() }

    let f = stream.finalValue()
    f.notify {
      result in
      do {
        _ = try result.getValue()
        XCTFail("not expected to get a value when \"final\" stream is closed")
      }
      catch { e.fulfill() }
    }

    f.close()
    d.forEach { stream.post($0) }

    waitForExpectations(timeout: 1.0, handler: nil)
    stream.close()
  }

  func testFinal3()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e = expectation(description: "observation onValue")

    let d = (0..<events).map { _ in nzRandom() }

    let f = stream.finalValue(DispatchQueue.global())
    f.notify {
      result in
      do {
        let value = try result.getValue()
        XCTAssert(value == d.first)
      }
      catch { e.fulfill() }
    }

    stream.post(d[0])
    stream.post(TestError())

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testReduce1()
  {
    let stream = PostBox<Int>(DispatchQueue.global(qos: .utility))
    let events = 11

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    let m = stream.reduce(0, +)
    m.notify {
      result in
      do {
        let value = try result.getValue()
        if value == (events-1)*events/2 { e1.fulfill() }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testReduce2()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onError")

    let m = stream.reduce(DispatchQueue(label: "test"), 0, {
      sum, e throws -> Int in
      guard sum <= events else { throw TestError() }
      return sum+e
    })
    m.notify {
      result in
      do {
        let value = try result.getValue()
        if value > events { e1.fulfill() }
      }
      catch is StreamCompleted { XCTFail() }
      catch { e2.fulfill() }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testCountEvents()
  {
    let stream = PostBox<Int>(DispatchQueue(label: "serial", qos: .default))
    let events = 10

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    let m = stream.countEvents(DispatchQueue.global(qos: .userInitiated))
    m.notify {
      result in
      do {
        let value = try result.getValue()
        XCTAssert(value == events, "Counted \(value) events instead of \(events)")
        if value == events { e1.fulfill() }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testCoalesce()
  {
    let stream = PostBox<Int>(DispatchQueue(label: "concurrent", qos: .utility, attributes: .concurrent))
    let events = 10

    let e1 = expectation(description: "observation onValue")
    let e2 = expectation(description: "observation onCompletion")

    let m = stream.map(transform: { i in Double(2*i) }).coalesce(DispatchQueue.global(qos: .userInitiated))
    m.notify {
      result in
      do {
        let value = try result.getValue()
        XCTAssert(value.count == events, "Coalesced \(value.count) events instead of \(events)")
        let reduced = value.reduce(0, +)
        if reduced == Double((events-1)*events) { e1.fulfill() }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }

    for i in 0..<events { stream.post(i) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
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
    XCTAssert(stream.requested == 0)

    let e1 = expectation(description: "split.0 onValue")
    let e2 = expectation(description: "split.0 onError")

    var a0 = [Int]()
    split.0.coalesce().notify {
      result in
      do {
        let value = try result.getValue()
        a0 = value
        if value.count == events { e1.fulfill() }
        else { print("a0 has \(a0.count) elements") }
      }
      catch StreamCompleted.normally { e2.fulfill() }
      catch { XCTFail() }
    }
    XCTAssert(split.0.requested == Int64.max)
    XCTAssert(split.1.requested == 0)
    XCTAssert(stream.requested == Int64.max, "stream.requested should have been updated synchronously")

    let e3 = expectation(description: "split.1 onValue")
    let e4 = expectation(description: "split.1 onError")

    var a1 = [Int]()
    let s1 = split.1.coalesce()
    s1.onValue {
      value in
      a1 = value
      if value.count == events { e3.fulfill() }
      else { print("a1 has \(a1.count) elements") }
    }
    s1.onCompletion { _ in e4.fulfill() }
    XCTAssert(split.1.requested == Int64.max)
    XCTAssert(s1.requested == 1)

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 0.1, handler: nil)

    XCTAssert(a0 == a1)
  }

  func testSplit2()
  {
    let stream = PostBox<Int>()
    let events = 10
    let splits = 3

    let e = expectation(description: "observation complete")

    let split = stream.split(count: splits)
    XCTAssert(stream.requested == 0)

    let merged = MergeStream<Int>()
    split.forEach(merged.merge)

    merged.countEvents().onValue {
      count in
      if count == splits*events { e.fulfill() }
      else { print(count) }
    }

    XCTAssert(stream.requested == Int64.max, "stream.requested has an unexpected value; probable race condition")
    for i in 0..<events { stream.post(i+1) }
    stream.close()
    merged.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testSplit3()
  {
    let stream = PostBox<Int>()
    let events = 10

    let e1 = expectation(description: "split.0 onValue")

    let split = stream.split()

    XCTAssert(split.0.requested == 0)
    XCTAssert(stream.requested == 0)

    split.0.coalesce().onValue {
      values in
      let count = values.count
      count == events ? e1.fulfill() : XCTFail("split.0 expected \(events) events, got \(count)")
    }

    XCTAssert(split.0.requested == Int64.max)
    XCTAssert(stream.requested == Int64.max)

    for i in 0..<events { stream.post(i+1) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)

    let e3 = expectation(description: "split.1 onCompletion")

    XCTAssert(split.1.state == .waiting)
    XCTAssert(split.1.requested == Int64.min)
    // any subscription attempt will fail

    split.1.onValue { _ in XCTFail("split.1 never had a non-zero request") }
    split.1.onError { _ in e3.fulfill() }

    XCTAssert(split.1.state == .ended)

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testSplit4()
  {
    let stream = PostBox<Int>()
    let split = stream.map(transform: {$0+1}).split()
    let events = 10

    let e1 = expectation(description: "\(events) events")
    let e2 = expectation(description: "1 event")

    split.0.countEvents().onValue {
      if $0 == events { e1.fulfill() }
    }

    let sem = DispatchSemaphore(value: 0)
    split.1.notify {
      result in
      do {
        let value = try result.getValue()
        if value == 1 { sem.signal() }
      }
      catch { e2.fulfill() }
    }

    stream.post(0)
    _ = sem.wait(timeout: DispatchTime.now() + 1)
    split.1.close()
    (1..<events).forEach { stream.post($0) }
    stream.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

//
//  mergeTests.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import ReactiveStreams

class mergeTests: XCTestCase
{
  func testMerge1()
  { // "merge" a single stream, ensure event count is correct
    let s = PostBox<Int>()

    let count = 10

    let merged = MergeStream.merge(streams: [s])

    let e1 = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, count)
      }
      catch is StreamCompleted { e1.fulfill() }
      catch {}
    }

    XCTAssertEqual(merged.requested, .max)
    XCTAssertEqual(s.requested, .max)

    let e2 = expectation(description: "posting ends")
    s.onCompletion { e2.fulfill() }

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge2()
  { // close merged stream before any events come through
    let s = PostBox<Int>()

    let count = 10

    let merged = s.merge(with: [])

    let e1 = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, 0)
      }
      catch is StreamCompleted { e1.fulfill() }
      catch { print(error) }
    }

    // merged stream is closed before any events come through,
    // therefore event count will be zero
    merged.close()

    let e2 = expectation(description: "posting ends")
    s.onCompletion { e2.fulfill() }

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge3()
  { // let two input streams complete
    let streams = [PostBox<Int>(), PostBox<Int>()]

    let count = 10

    let merged = MergeStream.merge(streams[0], streams[1])

    XCTAssertEqual(merged.requested, 0)
    XCTAssertEqual(streams[0].requested, 0)

    let c = merged.countEvents()
    let e = expectation(description: "merged stream ends \(#function)")
    c.onValue { XCTAssertEqual($0, count*streams.count) }
    c.onCompletion { e.fulfill() }

    XCTAssertEqual(merged.requested, .max)
    XCTAssertEqual(streams[0].requested, .max)
    XCTAssertEqual(c.requested, 1)

    for stream in streams
    {
      for i in 0..<count { stream.post(i+1) }
      let e = expectation(description: "posts end \(ObjectIdentifier(stream)) \(#function)")
      stream.onCompletion { e.fulfill() }
    }

    streams.forEach { $0.close() }

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge4()
  { // make merged stream error before all posted events come through
    let s = PostBox<Int>(qos: .utility)
    let t = PostBox<Int>(qos: .userInitiated)

    let posted = 10000
    let id = nzRandom()

    let merged = s.merge(with: [t])

    let e1 = expectation(description: "observation ends \(#function)")
    merged.countEvents().notify {
      event in
      do {
        let counted = try event.get()
        XCTAssertLessThan(counted, posted)
      }
      catch let error as TestError {
        if error.error == id { e1.fulfill() }
      }
      catch { XCTFail() }
    }

    let e2 = expectation(description: "posting ends")
    s.onCompletion { e2.fulfill() }

    s.post(0)
    t.post(TestError(id))
    for i in 1..<posted { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge5()
  { // merged stream states, stage-managed
    let s = PostBox<Int>()
    let e = expectation(description: "observation ends \(#function)")
    let count = 10

    let merged = EventStream.merge(queue: DispatchQueue.global(qos: .utility), streams: [s])
    merged.onValue { if $0 == count { e.fulfill() } }

    for i in 0..<count { s.post(i+1) }

    waitForExpectations(timeout: 1.0, handler: nil)

    let g = expectation(description: "observation ends \(#function)")

    merged.onCompletion { g.fulfill() }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge6()
  { // check propagation of error states
    let s = [PostBox<Int>(), PostBox<Int>()]
    let e = expectation(description: "observation ends \(#function)")

    let count = 10

    let merged = s[0].merge(with: s.dropFirst())

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssertEqual(value, (count + count/2), String(value))
      }
      catch let error as TestError {
        if error.error == count { e.fulfill() }
      }
      catch { XCTFail() }
    }

    for (n,stream) in s.enumerated()
    {
      for i in 0..<count
      {
        do {
          let v = (n+1)*i
          if v >= count { throw TestError(v) }
          stream.post(Event(value: v))
        }
        catch {
          stream.post(Event(error: error))
        }
      }

      let x = expectation(description: "posting ends")
      stream.notify { e in if !e.isValue { x.fulfill() } }
      stream.close()
    }

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge7()
  { // more stage-managed merged stream states
    let s1 = PostBox<Int>()
    let e1 = expectation(description: "s1")
    let c1 = s1.countEvents()
    c1.onValue { XCTAssertEqual($0, 1) }
    c1.onCompletion { e1.fulfill() }

    let merged = EventStream<Int>.merge(streams: []) as! MergeStream
    let e2 = expectation(description: "merged")
    let c2 = merged.countEvents()
    c2.onValue { XCTAssertEqual($0, 0) }
    c2.onCompletion { e2.fulfill() }

    merged.close()
    merged.merge(s1)
    s1.post(0)
    s1.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge8()
  { // test the merge method
    let s1 = PostBox<Int>()
    let g1 = DispatchGroup()
    g1.enter()
    let c1 = s1.countEvents()
    c1.onValue { XCTAssertEqual($0, 1) }
    c1.onCompletion { g1.leave() }

    let s2 = PostBox<Int>()
    let e2 = expectation(description: "s2")
    let c2 = s2.countEvents()
    c2.onValue { XCTAssertEqual($0, 2) }
    c2.onCompletion { e2.fulfill() }

    let m4 = s1.merge(with: s2)
    let e4 = expectation(description: "m4")
    let c4 = m4.countEvents()
    c4.notify {
      event in
      do {
        let count = try event.get()
        XCTAssertEqual(count, 3)
      }
      catch StreamCompleted.normally { e4.fulfill() }
      catch { XCTFail() }
    }

    s1.post(1)
    s2.post(1)
    s1.close()
    g1.wait()
    s2.post(2)
    s2.close()

    waitForExpectations(timeout: 0.1)
    m4.close()
  }

  func testMergeDelayingError1()
  {
    let posted = 1000
    let id = nzRandom()

    let s1 = PostBox<Int>(qos: .utility)
    let e1 = expectation(description: "postbox 1")
    s1.onCompletion { e1.fulfill() }

    let s2 = PostBox<Int>(qos: .utility)
    let e2 = expectation(description: "postbox 2")
    s2.notify { e in if !e.isValue { e2.fulfill() } }

    let m3 = EventStream.merge(streams: [s2, s1], delayingErrors: true)
    let e3 = expectation(description: "merge delaying errors")
    m3.countEvents().notify {
      e in
      do {
        let countedEvents = try e.get()
        XCTAssertEqual(countedEvents, posted)
      }
      catch TestError.value(let e) {
        XCTAssertEqual(e, id)
        e3.fulfill()
      }
      catch { XCTFail() }
    }

    s1.post(0)
    s2.post(0)
    s2.post(TestError(id))
    for i in 2..<posted { s1.post(i) }
    s1.close()

    waitForExpectations(timeout: 0.1)
  }

  func testMergeDelayingError2()
  {
    let id = nzRandom()

    let queue = DispatchQueue(label: "delaying error test")
    let streams = (0..<10).map { _ in PostBox<Int>(queue: queue) }

    let merged = EventStream.merge(streams: streams, delayingErrors: true)
    let x = expectation(description: "correct delayed error")
    merged.onError {
      error in
      XCTAssert(error is TestError)
      if let e = error as? TestError
      {
        XCTAssertEqual(e.error, id)
        x.fulfill()
      }
    }

    streams.first?.post(TestError(id))
    streams.dropFirst().forEach {
      $0.post(TestError(nzRandom()))
    }

    waitForExpectations(timeout: 0.1)
  }
}

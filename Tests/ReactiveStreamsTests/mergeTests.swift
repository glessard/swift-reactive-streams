//
//  mergeTests.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
@testable import ReactiveStreams

class mergeTests: XCTestCase
{
  func testMerge1()
  { // "merge" a single stream, ensure event count is correct
    let s = PostBox<Int>()

    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e1 = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == count)
      }
      catch is StreamCompleted { e1.fulfill() }
      catch {}
    }

    XCTAssert(merged.requested == .max)
    XCTAssert(s.requested == .max)

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

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e1 = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == 0)
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
  { // make merged stream error before any events come through
    let s = PostBox<Int>()

    let count = 0
    let id = nzRandom()

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == count)
      }
      catch let error as TestError {
        if error.error == id { e.fulfill() }
      }
      catch { XCTFail() }
    }

    merged.queue.async {
      merged.dispatch(Event(error: TestError(id)))
    }

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge4()
  { // let two input streams complete
    let streams = [PostBox<Int>(), PostBox<Int>()]

    let count = 10

    let merged = MergeStream<Int>()
    streams.forEach(merged.merge)

    XCTAssert(merged.requested == 0)
    XCTAssert(streams[0].requested == 0)

    let c = merged.countEvents()
    let e = expectation(description: "merged stream ends \(#function)")
    c.onValue { XCTAssert($0 == count*streams.count) }
    c.onCompletion { e.fulfill() }

    XCTAssert(merged.requested == .max)
    XCTAssert(streams[0].requested == .max)
    XCTAssert(c.requested == 1)

    for stream in streams
    {
      for i in 0..<count { stream.post(i+1) }
      let e = expectation(description: "posts end \(ObjectIdentifier(stream)) \(#function)")
      stream.onCompletion { e.fulfill() }
    }

    streams.forEach { $0.close() }

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge5()
  { // merged stream states, stage-managed
    let s = PostBox<Int>()
    let e = expectation(description: "observation ends \(#function)")
    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)
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

    let merged = MergeStream<Int>()
    s.forEach(merged.merge)

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == (count + count/2))
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
      stream.close()
      stream.queue.sync(execute: {})
    }

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge7()
  { // more stage-managed merged stream states
    let s1 = PostBox<Int>()
    let e1 = expectation(description: "s1")
    let c1 = s1.countEvents()
    c1.onValue { XCTAssert($0 == 1) }
    c1.onCompletion { e1.fulfill() }

    let merged = MergeStream<Int>()
    let e2 = expectation(description: "merged")
    let c2 = merged.countEvents()
    c2.onValue { XCTAssert($0 == 0) }
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
    let e1 = expectation(description: "s1")
    let c1 = s1.countEvents()
    c1.onValue { XCTAssert($0 == 1) }
    c1.onCompletion { e1.fulfill() }

    let s2 = PostBox<Int>()
    let e2 = expectation(description: "s2")
    let c2 = s2.countEvents()
    c2.onValue { XCTAssert($0 == 2) }
    c2.onCompletion { e2.fulfill() }

    let s3 = PostBox<Int>()
    let e3 = expectation(description: "s3")
    let c3 = s3.countEvents()
    c3.onValue { XCTAssert($0 == 3) }
    c3.onCompletion { e3.fulfill() }

    let m4 = s1.merge(with: s2)
    let e4 = expectation(description: "m4")
    let c4 = m4.countEvents()
    c4.notify {
      event in
      do {
        let count = try event.get()
        XCTAssert(count == 2, String(count))
      }
      catch StreamCompleted.normally { e4.fulfill() }
      catch { XCTFail() }
    }

    let m5 = m4.merge(with: s3)
    let e5 = expectation(description: "m5")
    let c5 = m5.countEvents()
    c5.notify {
      event in
      do {
        let count = try event.get()
        XCTAssert(count == 5, String(count))
      }
      catch StreamCompleted.normally { e5.fulfill() }
      catch { XCTFail() }
    }

    s1.post(1)
    s1.close()
    s1.queue.sync {}
    s2.post(2)
    s2.queue.sync {}
    m4.close()

    s2.post(2)
    s2.close()
    s3.post(3)
    s3.post(3)
    s3.post(3)
    s3.close()

    waitForExpectations(timeout: 0.1)
  }
}

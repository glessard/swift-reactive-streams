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
  static let allTests = [
    ("testMerge1", testMerge1),
    ("testMerge2", testMerge2),
    ("testMerge3", testMerge3),
    ("testMerge4", testMerge4),
    ("testMerge5", testMerge5),
    ("testMerge6", testMerge6),
    ("testMerge7", testMerge7),
    ("testMerge8", testMerge8),
  ]

  func testMerge1()
  {
    let s = PostBox<Int>()

    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == count)
      }
      catch is StreamCompleted { e.fulfill() }
      catch {}
    }

    for i in 0..<count { s.post(i+1) }
    s.close()

    merged.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge2()
  {
    let s = PostBox<Int>()

    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == count)
      }
      catch is StreamCompleted { e.fulfill() }
      catch { print(error) }
    }

    merged.close()

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge3()
  {
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
      merged.dispatchError(Event(error: TestError(id)))
    }

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge4()
  {
    let s = [PostBox<Int>(), PostBox<Int>()]
    let e = expectation(description: "observation ends \(#function)")

    let count = 10

    let merged = MergeStream<Int>()
    s.forEach(merged.merge)

    merged.countEvents().notify {
      event in
      do {
        let value = try event.get()
        XCTAssert(value == count*s.count)
      }
      catch is StreamCompleted { e.fulfill() }
      catch { XCTFail() }
    }
    merged.close()

    let q = DispatchQueue.global(qos: .utility)
    for stream in s
    {
      q.async {
        for i in 0..<count { stream.post(i+1) }
        stream.close()
      }
    }

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge5()
  {
    let s = PostBox<Int>()
    let e = expectation(description: "observation ends \(#function) #1")
    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)
    merged.onValue { if $0 == count { e.fulfill() } }

    for i in 0..<count { s.post(i+1) }

    waitForExpectations(timeout: 1.0, handler: nil)

    let f = expectation(description: "observation ends \(#function) #2")

    s.onCompletion { _ in f.fulfill() }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)

    let g = expectation(description: "observation ends \(#function) #3")

    merged.onCompletion { _ in g.fulfill() }
    merged.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge6()
  {
    let s = PostBox<Int>()
    let e = expectation(description: "observation ends \(#function)")
    let count = 10

    let merged = MergeStream<Int>()
    merged.merge(s)
    merged.onValue { if $0 == count { e.fulfill() } }

    for i in 0..<count { s.post(i+1) }
    s.close()

    waitForExpectations(timeout: 1.0, handler: nil)

    let g = expectation(description: "observation ends \(#function)")

    merged.onCompletion { _ in g.fulfill() }
    merged.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testMerge7()
  {
    let s = [PostBox<Int>(), PostBox<Int>()]
    let e = expectation(description: "observation ends \(#function)")

    let count = 10

    let merged = MergeStream<Int>()
    s.forEach(merged.merge)
    merged.close()

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

  func testMerge8()
  {
    let s1 = PostBox<Int>()
    let e1 = expectation(description: "s1")
    s1.onCompletion { _ in e1.fulfill() }

    let merged = MergeStream<Int>()
    let e2 = expectation(description: "merged")
    merged.onCompletion { _ in e2.fulfill() }

    merged.close()
    merged.merge(s1)
    s1.close()

    waitForExpectations(timeout: 1.0, handler: nil)
  }
}

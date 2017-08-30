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
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
      }
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
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error):
        e.fulfill()
        if error is StreamCompleted {}
        else { print(error) }
      }
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

    let merged = MergeStream<Int>()
    merged.merge(s)

    let e = expectation(description: "observation ends \(#function)")

    merged.countEvents().notify {
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count)
        if value != count { print(value) }
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default:
        XCTFail()
      }
    }

    // merged.post(Result.error(NSError(domain: "bogus", code: -1, userInfo: nil)))
    merged.queue.async {
      merged.dispatchError(Result.error(NSError(domain: "bogus", code: -1, userInfo: nil)))
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
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == count*s.count)
        if value != count*s.count { print(value) }
      case .error(let error):
        if error is StreamCompleted { e.fulfill() }
      }
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
      result in
      switch result
      {
      case .value(let value):
        XCTAssert(value == (count + count/2))
        if value != (count + count/2) { print(value) }
      case .error(let error as NSError):
        if error.domain == "bogus" { e.fulfill() }
        else { print(error) }
      default:
        XCTFail()
      }
    }

    for (n,stream) in s.enumerated()
    {
      for i in 0..<count
      {
        stream.post(Result.value((n+1)*i).map({
          v throws -> Int in
          if v < count { return v }
          throw NSError(domain: "bogus", code: -1, userInfo: nil)
        }))
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

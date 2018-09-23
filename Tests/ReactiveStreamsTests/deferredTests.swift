//
//  File.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import ReactiveStreams

class deferredTests: XCTestCase
{
  func testNext() throws
  {
    let stream = PostBox<Int>()

    let events = 100
    let limit = 5

    let m = stream.skip(count: limit).next()

    XCTAssert(stream.requested == Int64(limit+1))

    for i in 0..<events { stream.post(i) }
    stream.close()

    let value = try m.get()
    XCTAssert(value == limit)
  }
}

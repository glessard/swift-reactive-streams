//
//  DispatchUtilitiesTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 9/15/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

import ReactiveStreams


class DispatchUtilitiesTests: XCTestCase
{
  func testCurrent()
  {
    let requested = DispatchQoS(qosClass: .userInitiated, relativePriority: -1)
    let q = DispatchQueue(label: "", qos: requested)

    let e = expectation(description: "\(#function)")
    q.async {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      let current = DispatchQoS.current
      XCTAssert(current.qosClass == requested.qosClass)
      XCTAssert(current.relativePriority == 0) // can't get relative priority without knowing the queue
      XCTAssert(q.qos == requested)
#else
      XCTAssert(q.qos == .unspecified, "swift-corelibs-libdispatch has changed")
#endif
      e.fulfill()
    }

    waitForExpectations(timeout: 0.1)
  }
}

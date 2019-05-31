//
//  TestError.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-09-24.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

enum TestError: Error, Equatable
{
  case value(Int)

  var error: Int {
    switch self { case .value(let v): return v }
  }

  init(_ e: Int = 0) { self = .value(e) }
}

func ~= <EquatableError>(match: EquatableError, error: Error?) -> Bool
  where EquatableError: Error & Equatable
{
  return match == (error as? EquatableError)
}

import XCTest

func XCTAssertErrorEquals<EquatableError>(_ error: Error?, _ target: EquatableError,
                                          _ message: @autoclosure () -> String = "",
                                          file: StaticString = #file, line: UInt = #line)
  where EquatableError: Error & Equatable
{
  if let e = error as? EquatableError
  {
    XCTAssertEqual(e, target, message(), file: file, line: line)
  }
  else if let d = error.map(String.init(describing:))
  {
    XCTAssertEqual(d, String(describing: target), message(), file: file, line: line)
  }
  else
  {
    XCTAssertEqual(Optional<EquatableError>.none, target, message(), file: file, line: line)
  }
}

func XCTAssertErrorNotEqual<EquatableError>(_ error: Error?, _ target: EquatableError,
                                            _ message: @autoclosure () -> String = "",
                                            file: StaticString = #file, line: UInt = #line)
  where EquatableError: Error & Equatable
{
  if let e = error as? EquatableError
  {
    XCTAssertNotEqual(e, target, message(), file: file, line: line)
  }
  else if let d = error.map(String.init(describing:))
  {
    XCTAssertNotEqual(d, String(describing: target), message(), file: file, line: line)
  }
  else
  {
    XCTAssertNotEqual(Optional<EquatableError>.none, target, message(), file: file, line: line)
  }
}

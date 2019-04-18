//
//  event.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

#if compiler(>=5.0)

public typealias Event<Value> = Result<Value, Error>

extension Result where Failure == Error
{
  @inlinable
  public init(value: Success)
  {
    self = .success(value)
  }

  @inlinable
  public init(error: Error)
  {
    self = .failure(error)
  }

  @inlinable
  public init(final: StreamCompleted)
  {
    self = .failure(final)
  }

  @inlinable
  public var value: Success? {
    if case .success(let value) = self { return value }
    return nil
  }

  @inlinable
  public var error: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }

  @inlinable
  public var isValue: Bool {
    if case .success = self { return true }
    return false
  }

  @inlinable
  public var isError: Bool {
    if case .failure = self { return true }
    return false
  }

  public static var streamCompleted: Result<Success, Error> {
    return .failure(StreamCompleted.normally)
  }

  @inlinable
  public var streamCompleted: StreamCompleted? {
    if case .failure(let final as StreamCompleted) = self { return final }
    return nil
  }

  @inlinable
  public var streamError: Error?
  {
    guard case .failure(let error) = self else { return nil }
    if (error as? StreamCompleted) == .normally { return nil }
    return error
  }
}

#else

import Outcome

public typealias Event = Outcome

extension Event
{
  public init(final: StreamCompleted)
  {
    self.init(error: final)
  }

  public static var streamCompleted: Event<Value> {
    return Event(final: StreamCompleted.normally)
  }

  public var streamCompleted: StreamCompleted? {
    return self.error as? StreamCompleted
  }

  public var streamError: Error? {
    guard let error = error else { return nil }
    if (error as? StreamCompleted) == .normally { return nil }
    return error
  }
}

#endif

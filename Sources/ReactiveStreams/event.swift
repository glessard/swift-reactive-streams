//
//  event.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import class Foundation.NSError

public struct Event<Value>
{
  @usableFromInline var state: Result<Value, Swift.Error>?

  private init(state: Result<Value, Swift.Error>?)
  {
    self.state = state
  }

  @inlinable
  public init(value: Value)
  {
    state = .success(value)
  }

  @inlinable
  public init(error: Error?)
  {
    assert((error as? StreamCompleted) != StreamCompleted())
    state = error.map(Result.failure(_:))
  }

  public static var streamCompleted: Event {
    return Event(state: nil)
  }

  @inlinable
  public func get() throws -> Value
  {
    switch state
    {
    case .success(let value)?: return value
    case .failure(let error)?: throw error
    case .none:                throw StreamCompleted()
    }
  }

  @inlinable
  public var value: Value? {
    if case .success(let value)? = state { return value }
    return nil
  }

  @inlinable
  public var error: Error? {
    if case .failure(let error)? = state { return error }
    return nil
  }

  @inlinable
  public var completedNormally: Bool {
    return state == nil
  }

  @inlinable
  public var isValue: Bool {
    if case .success? = state { return true }
    return false
  }

  @inlinable
  public var isError: Bool {
    if case .failure? = state { return true }
    return false
  }
}

extension Event: CustomStringConvertible
{
  public var description: String {
    switch state
    {
    case .success(let value)?: return "Value: \(value)"
    case .failure(let error)?: return "Error: \(error)"
    case nil:                  return "Stream Completed"
    }
  }
}

extension Event: Equatable where Value: Equatable
{
  public static func ==(lhe: Event, rhe: Event) -> Bool
  {
    switch (lhe.state, rhe.state)
    {
    case (nil, nil):
      return true
    case (.success(let lhv)?, .success(let rhv)?):
      return lhv == rhv
    case (.failure(let lhe)?, .failure(let rhe)?):
      let lhs = "\(lhe) \(lhe as NSError)"
      let rhs = "\(rhe) \(rhe as NSError)"
      return lhs == rhs
    default:
      return false
    }
  }
}

extension Event: Hashable where Value: Hashable
{
  public func hash(into hasher: inout Hasher)
  {
    switch state
    {
    case nil:
      Int(0).hash(into: &hasher)
    case .success(let value)?:
      Int(1).hash(into: &hasher)
      value.hash(into: &hasher)
    case .failure(let error)?:
      Int(2).hash(into: &hasher)
      "\(error) \(error as NSError)".hash(into: &hasher)
    }
  }
}

extension Event
{
  public init(_ result: Result<Value, Error>)
  {
    self.result = result
  }

  @inlinable
  public var result: Result<Value, Error>? {
    get { return state }
    set {
      if case .failure(let error)? = newValue, error is StreamCompleted
      {
        state = nil
        return
      }

      state = newValue
    }
  }
}

public struct StreamCompleted: Error, Equatable, Hashable
{
  @usableFromInline init() {}
}

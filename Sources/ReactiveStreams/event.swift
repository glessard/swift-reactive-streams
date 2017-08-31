//
//  event.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

public enum Event<Value>
{
  case value(Value)
  // The error case does not encode type beyond the Error protocol.
  // This way there is no need to map between error types, which mostly cannot make sense.
  case error(Error)

  public init(task: () throws -> Value)
  {
    do {
      let value = try task()
      self = .value(value)
    }
    catch {
      self = .error(error)
    }
  }

  public init(value: Value)
  {
    self = .value(value)
  }

  public init(final: StreamCompleted)
  {
    self = .error(final)
  }

  public init(error: Error)
  {
    self = .error(error)
  }

  public init(_ optional: Value?, or error: Error)
  {
    switch optional
    {
    case .some(let value): self = .value(value)
    case .none:            self = .error(error)
    }
  }

  public var value: Value? {
    switch self
    {
    case .value(let value): return value
    case .error:            return nil
    }
  }

  public var isValue: Bool {
    switch self
    {
    case .value: return true
    case .error: return false
    }
  }

  public var final: StreamCompleted? {
    if case .error(let final as StreamCompleted) = self
    { return final }
    else
    { return nil }
  }

  public var error: Error? {
    if case .error(let error) = self, !(error is StreamCompleted)
    { return error }
    else
    { return nil }
  }

  public func getValue() throws -> Value
  {
    switch self
    {
    case .value(let value): return value
    case .error(let error): throw error
    }
  }

  public func map<Other>(_ transform: (Value) throws -> Other) -> Event<Other>
  {
    switch self
    {
    case .value(let value): return Event<Other> { try transform(value) }
    case .error(let error): return .error(error)
    }
  }

  public func flatMap<Other>(_ transform: (Value) -> Event<Other>) -> Event<Other>
  {
    switch self
    {
    case .value(let value): return transform(value)
    case .error(let error): return .error(error)
    }
  }

  public func recover(_ transform: (Error) -> Event) -> Event
  {
    switch self
    {
    case .value:            return self
    case .error(let error): return transform(error)
    }
  }
}

extension Event: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .value(let value): return String(describing: value)
    case .error(let final as StreamCompleted): return "\(final)"
    case .error(let error): return "Error: \(error)"
    }
  }
}

public func ?? <Value> (possible: Event<Value>, alternate: @autoclosure () -> Value) -> Value
{
  switch possible
  {
  case .value(let value): return value
  case .error:            return alternate()
  }
}

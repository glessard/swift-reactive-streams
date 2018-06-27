//
//  event.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

public struct Event<Value>
{
  fileprivate let state: State<Value>

  private init(task: () throws -> Value)
  {
    do {
      let value = try task()
      state = .value(value)
    }
    catch {
      state = .error(error)
    }
  }

  public init(value: Value)
  {
    state = .value(value)
  }

  public init(final: StreamCompleted)
  {
    state = .error(final)
  }

  public init(error: Error)
  {
    state = .error(error)
  }

  public func get() throws -> Value
  {
    switch state
    {
    case .value(let value): return value
    case .error(let error): throw error
    }
  }

  public var value: Value? {
    if case .value(let value) = state { return value }
    return nil
  }

  public var isValue: Bool {
    if case .value = state { return true }
    return false
  }

  public var final: StreamCompleted? {
    if case .error(let final as StreamCompleted) = state
    { return final }
    else
    { return nil }
  }

  public var error: Error? {
    if case .error(let error) = state, !(error is StreamCompleted)
    { return error }
    else
    { return nil }
  }

  public func map<Other>(_ transform: (Value) throws -> Other) -> Event<Other>
  {
    switch state
    {
    case .value(let value): return Event<Other> { try transform(value) }
    case .error(let error): return Event<Other>(error: error)
    }
  }

  public func flatMap<Other>(_ transform: (Value) -> Event<Other>) -> Event<Other>
  {
    switch state
    {
    case .value(let value): return transform(value)
    case .error(let error): return Event<Other>(error: error)
    }
  }

  public func recover(_ transform: (Error) -> Event) -> Event
  {
    switch state
    {
    case .value:            return self
    case .error(let error): return transform(error)
    }
  }
}

extension Event: CustomStringConvertible
{
  public var description: String {
    switch state
    {
    case .value(let value): return String(describing: value)
    case .error(let final as StreamCompleted): return "\(final)"
    case .error(let error): return "Error: \(error)"
    }
  }
}

#if swift (>=4.1)
extension Event: Equatable where Value: Equatable
{
  public static func ==(lhs: Event, rhs: Event) -> Bool
  {
    switch (lhs.state, rhs.state)
    {
    case (.value(let lhv), .value(let rhv)):
      return lhv == rhv
    case (.error(let lhe), .error(let rhe)):
      return String(describing: lhe) == String(describing: rhe)
    default:
      return false
    }
  }
}
#endif

#if swift (>=4.2)
@usableFromInline
enum State<Value>
{
  case value(Value)
  case error(Error)
}
#else
enum State<Value>
{
  case value(Value)
  case error(Error)
}
#endif

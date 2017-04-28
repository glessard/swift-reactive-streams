//
//  stream-reduce.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension EventStream
{
  private func reduce<U>(_ stream: LimitedStream<Value, U>, initial: U, combine: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(stream, initial: initial) { $0 = try combine($0, $1) }
  }

  private func reduce<U>(_ stream: LimitedStream<Value, U>, initial: U, combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    var current = initial
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        subscription.requestAll()
        stream.setSubscription(subscription)
      },
      notificationHandler: {
        mapped, result in
        mapped.queue.async {
          switch result
          {
          case .value(let value):
            do {
              try combine(&current, value)
            }
            catch {
              mapped.dispatchValue(Result.value(current))
              mapped.dispatchError(Result.error(error))
            }
          case .error(let error):
            mapped.dispatchValue(Result.value(current))
            mapped.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func reduce<U>(_ initial: U, _ combining: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: DispatchQoS.current(), count: 1), initial: initial, combine: combining)
  }

  public func reduce<U>(qos: DispatchQoS, initial: U, _ combining: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos, count: 1), initial: initial, combine: combining)
  }

  public func reduce<U>(queue: DispatchQueue, initial: U, _ combining: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(queue: queue, count: 1), initial: initial, combine: combining)
  }

  public func reduce<U>(_ initial: U, combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: DispatchQoS.current(), count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(qos: DispatchQoS, initial: U, combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos, count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(queue: DispatchQueue, initial: U, combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(queue: queue, count: 1), initial: initial, combine: combine)
  }
}

extension EventStream
{
  public func countEvents(qos: DispatchQoS = DispatchQoS.current()) -> EventStream<Int>
  {
    return self.reduce(qos: qos, initial: 0) { (count: inout Int, _) in count += 1 }
  }

  public func countEvents(queue: DispatchQueue) -> EventStream<Int>
  {
    return self.reduce(queue: queue, initial: 0) { (count: inout Int, _) in count += 1 }
  }
}

extension EventStream
{

  public func coalesce(qos: DispatchQoS = DispatchQoS.current()) -> EventStream<[Value]>
  {
    return self.reduce(qos: qos, initial: [], combine: { $0.append($1) })
  }
  
  public func coalesce(queue: DispatchQueue) -> EventStream<[Value]>
  {
    return self.reduce(queue: queue, initial: [], combine: { $0.append($1) })
  }
}

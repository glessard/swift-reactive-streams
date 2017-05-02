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
    return reduce(stream, into: initial) { $0 = try combine($0, $1) }
  }

  private func reduce<U>(_ stream: LimitedStream<Value, U>, into initial: U, combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
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

  public func reduce<U>(qos: DispatchQoS? = nil, _ initial: U, _ combine: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos ?? self.qos, count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(_ queue: DispatchQueue, _ initial: U, _ combine: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(queue, count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(qos: DispatchQoS? = nil, into: U, _ combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos ?? self.qos, count: 1), into: into, combine: combine)
  }

  public func reduce<U>(_ queue: DispatchQueue, into: U, _ combine: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    return reduce(LimitedStream<Value, U>(queue, count: 1), into: into, combine: combine)
  }
}

extension EventStream
{
  public func countEvents(qos: DispatchQoS? = nil) -> EventStream<Int>
  {
    return self.reduce(qos: qos, into: 0) { (count: inout Int, _) in count += 1 }
  }

  public func countEvents(_ queue: DispatchQueue) -> EventStream<Int>
  {
    return self.reduce(queue, into: 0) { (count: inout Int, _) in count += 1 }
  }
}

extension EventStream
{

  public func coalesce(qos: DispatchQoS? = nil) -> EventStream<[Value]>
  {
    return self.reduce(qos: qos, into: []) { $0.append($1) }
  }
  
  public func coalesce(_ queue: DispatchQueue) -> EventStream<[Value]>
  {
    return self.reduce(queue, into: []) { $0.append($1) }
  }
}

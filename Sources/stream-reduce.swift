//
//  stream-reduce.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension Stream
{
  private func reduce<U>(stream: LimitedStream<Value, U>, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
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
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value(let value):
            do {
              current = try combine(current, value)
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

  public func reduce<U>(initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos_class_self(), count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(qos qos: qos_class_t, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos, count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(queue queue: dispatch_queue_t, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(queue: queue, count: 1), initial: initial, combine: combine)
  }
}

extension Stream
{
  private func countEvents(stream: LimitedStream<Value, Int>) -> Stream<Int>
  {
    var total = 0
    self.subscribe(subscriber: stream,
                   subscriptionHandler: {
                    subscription in
                    stream.setSubscription(subscription)
                    subscription.requestAll()
      },
                   notificationHandler: {
                    mapped, result in
                    dispatch_async(mapped.queue) {
                      switch result
                      {
                      case .value:
                        total += 1
                      case .error(let error):
                        mapped.dispatchValue(Result.value(total))
                        mapped.dispatchError(Result.error(error))
                      }
                    }
      }
    )
    return stream
  }

  public func countEvents(qos qos: qos_class_t = qos_class_self()) -> Stream<Int>
  {
    return countEvents(LimitedStream<Value, Int>(qos: qos, count: 1))
  }

  public func countEvents(queue queue: dispatch_queue_t) -> Stream<Int>
  {
    return countEvents(LimitedStream<Value, Int>(queue: queue, count: 1))
  }
}

extension Stream
{
  private func coalesce(stream: LimitedStream<Value, [Value]>) -> Stream<[Value]>
  {
    var current = [Value]()
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        stream.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value(let value):
            current.append(value)
          case .error(let error):
            mapped.dispatchValue(Result.value(current))
            mapped.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func coalesce(qos qos: qos_class_t = qos_class_self()) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<Value, [Value]>(qos: qos, count: 1))
  }
  
  public func coalesce(queue queue: dispatch_queue_t) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<Value, [Value]>(queue: queue, count: 1))
  }
}

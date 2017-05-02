//
//  stream-next.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension EventStream
{
  private func next(_ stream: LimitedStream<Value, Value>) -> EventStream<Value>
  {
    let limit = stream.limit
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, result in
        mapped.queue.async {
          switch mapped.count+1
          {
          case let c where c < limit:
            mapped.count = c
            mapped.dispatch(result)
          case limit:
            mapped.count = limit
            mapped.dispatch(result)
            if case .value = result { mapped.close() }
          default:
            break
          }
          return
        }
      }
    )
    return stream
  }

  public func next(qos: DispatchQoS = DispatchQoS.current(), count: Int = 1) -> EventStream<Value>
  {
    return next(LimitedStream<Value, Value>(qos: qos, count: Int64(max(count, 0))))
  }

  public func next(_ queue: DispatchQueue, count: Int = 1) -> EventStream<Value>
  {
    return next(LimitedStream<Value, Value>(queue, count: Int64(max(count, 0))))
  }
}

extension EventStream
{
  private func finalValue(_ stream: LimitedStream<Value, Value>) -> EventStream<Value>
  {
    var last: Value? = nil
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
            last = value
          case .error:
            if let value = last { mapped.dispatchValue(Result.value(value)) }
            mapped.dispatchError(result)
          }
        }
      }
    )
    return stream
  }

  public func finalValue(qos: DispatchQoS = DispatchQoS.current()) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value, Value>(qos: qos, count: 1))
  }

  public func finalValue(_ queue: DispatchQueue) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value, Value>(queue, count: 1))
  }
}

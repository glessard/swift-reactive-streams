//
//  stream-next.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension Stream
{
  private func next(stream: LimitedStream<Value, Value>) -> Stream<Value>
  {
    let limit = stream.limit
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
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

  public func next(qos qos: qos_class_t = qos_class_self(), count: Int = 1) -> Stream<Value>
  {
    return next(LimitedStream<Value, Value>(qos: qos, count: Int64(max(count, 0))))
  }

  public func next(queue queue: dispatch_queue_t, count: Int = 1) -> Stream<Value>
  {
    return next(LimitedStream<Value, Value>(queue: queue, count: Int64(max(count, 0))))
  }
}

extension Stream
{
  private func final(stream: LimitedStream<Value, Value>) -> Stream<Value>
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
        dispatch_async(mapped.queue) {
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

  public func final(qos qos: qos_class_t = qos_class_self()) -> Stream<Value>
  {
    return final(LimitedStream<Value, Value>(qos: qos, count: 1))
  }

  public func final(queue queue: dispatch_queue_t) -> Stream<Value>
  {
    return final(LimitedStream<Value, Value>(queue: queue, count: 1))
  }
}

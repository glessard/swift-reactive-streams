//
//  stream-next.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func next(_ stream: LimitedStream<Value, Value>) -> EventStream<Value>
  {
    let limit = stream.limit
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, event in
        mapped.queue.async {
          switch mapped.count+1
          {
          case let c where c < limit:
            mapped.count = c
            mapped.dispatch(event)
          case limit:
            mapped.count = limit
            mapped.dispatch(event)
            if case .value = event { mapped.close() }
          default:
            break
          }
          return
        }
      }
    )
    return stream
  }

  public func next(qos: DispatchQoS? = nil, count: Int = 1) -> EventStream<Value>
  {
    return next(LimitedStream<Value, Value>(qos: qos ?? self.qos, count: Int64(max(count, 0))))
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
    var latest: Event<Value>? = nil
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        subscription.requestAll()
        stream.setSubscription(subscription)
      },
      notificationHandler: {
        mapped, event in
        mapped.queue.async {
          switch event
          {
          case .value:
            latest = event
          case .error:
            if let latest = latest { mapped.dispatchValue(latest) }
            mapped.dispatchError(event)
          }
        }
      }
    )
    return stream
  }

  public func finalValue(qos: DispatchQoS? = nil) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value, Value>(qos: qos ?? self.qos, count: 1))
  }

  public func finalValue(_ queue: DispatchQueue) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value, Value>(queue, count: 1))
  }
}

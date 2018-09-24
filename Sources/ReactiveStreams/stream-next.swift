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
            if event.isValue { mapped.close() }
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
    return next(LimitedStream<Value, Value>(qos: qos ?? self.qos, count: Int64(count)))
  }

  public func next(_ queue: DispatchQueue, count: Int = 1) -> EventStream<Value>
  {
    return next(LimitedStream<Value, Value>(queue, count: Int64(count)))
  }
}

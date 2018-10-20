//
//  stream-final.swift
//  stream
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func finalValue(_ stream: LimitedStream<Value>) -> EventStream<Value>
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
          if event.isValue
          {
            latest = event
          }
          else
          {
            if let latest = latest { mapped.dispatch(latest) }
            mapped.dispatch(event)
          }
        }
    }
    )
    return stream
  }

  public func finalValue(qos: DispatchQoS? = nil) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value>(qos: qos ?? self.qos, count: 1))
  }

  public func finalValue(queue: DispatchQueue) -> EventStream<Value>
  {
    return finalValue(LimitedStream<Value>(queue: queue, count: 1))
  }
}

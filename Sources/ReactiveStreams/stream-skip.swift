//
//  stream-skip.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func skip(_ stream: SubStream<Value>, count: Int) -> EventStream<Value>
  {
    var skipped = 0
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        sub in
        stream.setSubscription(sub)
        sub.request(count)
      },
      notificationHandler: {
        stream, event in
        if event.isValue && skipped != count
        {
          skipped += 1
          return
        }

        stream.queue.async { stream.dispatch(event) }
      }
    )
    return stream
  }

  public func skip(qos: DispatchQoS? = nil, count: Int) -> EventStream<Value>
  {
    return skip(SubStream<Value>(qos: qos ?? self.qos), count: count)
  }

  public func skip(queue: DispatchQueue, count: Int) -> EventStream<Value>
  {
    return skip(SubStream<Value>(queue: queue), count: count)
  }
}

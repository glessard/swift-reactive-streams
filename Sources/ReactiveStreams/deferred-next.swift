//
//  deferred-next.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/22/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

extension EventStream
{
  public func next(qos: DispatchQoS? = nil) -> Deferred<Value>
  {
    let queue = DispatchQueue(label: "stream-to-deferred", qos: qos ?? self.qos)
    return next(queue: queue)
  }

  public func next(queue: DispatchQueue) -> Deferred<Value>
  {
    let subscriber = SingleValueSubscriber<Value>(queue: queue)

    self.subscribe(
      subscriber: subscriber,
      subscriptionHandler: {
        subscription in
        subscriber.setSubscription(subscription)
        subscription.request(1)
      },
      notificationHandler: { $0.determine($1) }
    )

    return Transferred(from: subscriber, on: queue)
  }
}

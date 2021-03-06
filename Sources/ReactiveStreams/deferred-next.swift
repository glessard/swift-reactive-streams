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
  public func next(qos: DispatchQoS? = nil) -> Deferred<Value, Error>
  {
    let queue = DispatchQueue(label: "stream-to-deferred", qos: qos ?? self.qos)
    return next(queue: queue)
  }

  public func next(queue: DispatchQueue) -> Deferred<Value, Error>
  {
    return SingleValueSubscriber<Value>(queue: queue) {
      resolver in
      var sub: Subscription? = nil

      self.subscribe(
        subscriptionHandler: {
          subscription in
          sub = subscription
          subscription.request(1)
        },
        notificationHandler: { resolver.resolve($1) }
      )
      return sub.unsafelyUnwrapped
    }
  }
}

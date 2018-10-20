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
    let tbd = TBD<Value>(queue: queue)
    var deferred: SingleValueSubscriber<Value>!

    self.subscribe(
      subscriber: tbd,
      subscriptionHandler: {
        subscription in
        deferred = SingleValueSubscriber(tbd, subscription: subscription)
        subscription.request(1)
      },
      notificationHandler: { $0.determine($1) }
    )

    return deferred
  }
}

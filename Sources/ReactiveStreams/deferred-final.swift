//
//  deferred-final.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 10/20/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

extension EventStream
{
  public func finalOutcome(qos: DispatchQoS? = nil) -> Deferred<Value>
  {
    let queue = DispatchQueue(label: "final-outcome", qos: qos ?? self.qos)
    return finalOutcome(queue: queue)
  }

  public func finalOutcome(queue: DispatchQueue) -> Deferred<Value>
  {
    let tbd = TBD<Value>(queue: queue)
    let deferred = SingleValueSubscriber(tbd)
    var latest: Value? = nil

    self.subscribe(
      subscriber: tbd,
      subscriptionHandler: {
        subscription in
        deferred.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        tbd, event in
        queue.async {
          do {
            latest = try event.get()
          }
          catch StreamCompleted.normally {
            let event = latest.map(Event.init(value:))
            let error = DeferredError.canceled("Source stream terminated without producing a value")
            tbd.determine(event ?? Event(error: error))
          }
          catch {
            tbd.determine(event)
          }
        }
      }
    )

    return deferred
  }
}

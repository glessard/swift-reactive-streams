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
    let subscriber = SingleValueSubscriber<Value>(queue: queue)
    var latest: Value? = nil

    self.subscribe(
      subscriber: subscriber,
      subscriptionHandler: {
        subscription in
        subscriber.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        subscriber, event in
        do {
          latest = try event.get()
        }
        catch StreamCompleted.normally {
          if let value = latest
          {
            subscriber.determine(Event(value: value))
          }
          else
          {
            subscriber.cancel("Source stream completed without producing a value")
          }
        }
        catch {
          subscriber.determine(event)
        }
      }
    )

    return Transferred(from: subscriber, on: queue)
  }
}

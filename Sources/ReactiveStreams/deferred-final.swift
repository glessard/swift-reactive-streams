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
    return SingleValueSubscriber<Value>(queue: queue) {
      resolver in
      var sub: Subscription? = nil
      var latest: Value? = nil

      self.subscribe(
        subscriptionHandler: {
          subscription in
          sub = subscription
          subscription.requestAll()
        },
        notificationHandler: {
          event in
          do {
            latest = try event.get()
          }
          catch StreamCompleted.normally {
            if let value = latest
            {
#if compiler(>=5.0)
              resolver.resolve(.success(value))
#else
              resolver.resolve(Event(value: value))
#endif
            }
            else
            {
              resolver.cancel("Source stream completed without producing a value")
            }
          }
          catch {
            resolver.resolve(event)
          }
        }
      )
      return sub.unsafelyUnwrapped
    }
  }
}

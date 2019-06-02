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
          _, event in
          switch event.state
          {
          case .success(let value)?:
            latest = value
          case .failure?:
            resolver.resolve(event)
          case nil:
            _ = latest.map { resolver.resolve(value: $0) } ??
                resolver.cancel("Source stream completed without producing a value")
          }
        }
      )
      return sub.unsafelyUnwrapped
    }
  }
}

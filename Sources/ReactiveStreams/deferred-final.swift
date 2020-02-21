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
  public func finalOutcome(qos: DispatchQoS? = nil) -> Deferred<Value, Error>
  {
    let queue = DispatchQueue(label: "final-outcome", qos: qos ?? self.qos)
    return finalOutcome(queue: queue)
  }

  public func finalOutcome(queue: DispatchQueue) -> Deferred<Value, Error>
  {
    return SingleValueSubscriber<Value>(queue: queue) {
      resolver in
      var sub: Subscription? = nil
      var latest: Event<Value>? = nil

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
          case .success?:
            latest = event
          case .failure?:
            resolver.resolve(event)
          case nil:
            _ = latest?.result.map { resolver.resolve($0) } ??
                resolver.cancel("Source stream completed without producing a value")
          }
        }
      )
      return sub.unsafelyUnwrapped
    }
  }
}

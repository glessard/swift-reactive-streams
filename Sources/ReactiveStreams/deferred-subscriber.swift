//
//  deferred-subscriber.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/22/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

public class SingleValueSubscriber<Value>: Deferred<Value, Error>
{
  private let subscription = LockedSubscription()

  public init(queue: DispatchQueue, task: @escaping (Resolver<Value, Error>) -> Subscription)
  {
    super.init(notifyingOn: queue) {
      [s = self.subscription] resolver in
      let subscription = task(resolver)
      resolver.notify { subscription.cancel() }
      s.assign(subscription)
    }
  }

  deinit {
    let s = subscription.take()
    s?.cancel()
  }

  public func requestAll()
  {
    request(Int64.max)
  }

  public func request(_ additional: Int64)
  {
    let s = subscription.load()
    s?.request(additional)
  }
}

extension Resolver where Failure == Error
{
  public func resolve(_ event: Event<Success>)
  {
    resolve(event.result ?? .failure(StreamCompleted()))
  }
}

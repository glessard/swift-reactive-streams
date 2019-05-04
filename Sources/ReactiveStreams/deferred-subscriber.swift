//
//  deferred-subscriber.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/22/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred
import CAtomics

public class SingleValueSubscriber<Value>: TBD<Value>
{
  private weak var subscription: Subscription? = nil

  public init(queue: DispatchQueue, execute: (Resolver<Value>) -> Subscription)
  {
    var resolver: Resolver<Value>!
    super.init(queue: queue) { resolver = $0 }

    let subscription = execute(resolver)
    resolver.notify { [weak subscription] in subscription?.cancel() }
    resolver.retainSource(subscription)
    self.subscription = subscription
  }

  deinit {
    subscription?.cancel()
  }

  public func requestAll()
  {
    request(Int64.max)
  }

  public func request(_ additional: Int64)
  {
    subscription?.request(additional)
  }
}

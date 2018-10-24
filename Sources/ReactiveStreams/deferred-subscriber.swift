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
  private var sub = OpaqueUnmanagedHelper()

  public override init(queue: DispatchQueue)
  {
    sub.initialize(nil)
    super.init(queue: queue)
    self.enqueue(task: {
      [weak self] _ in
      let subscription = self?.sub.take()
      subscription?.cancel()
    })
  }

  deinit {
    let subscription = sub.take()
    subscription?.cancel()
  }

  open func setSubscription(_ subscription: Subscription)
  {
    assert(sub.rawLoad(.sequential) == nil, "SingleValueSubscriber cannot subscribe to multiple streams")
    sub.initialize(subscription)
  }

  public func requestAll()
  {
    request(Int64.max)
  }

  public func request(_ additional: Int64)
  {
    let subscription = sub.load()
    subscription?.request(additional)
  }
}

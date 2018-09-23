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

public class SingleValueSubscriber<Value>: Transferred<Value>
{
  private var sub = OpaqueUnmanagedHelper()

  init(_ source: TBD<Value>, subscription: Subscription)
  {
    sub.initialize(subscription)
    super.init(from: source)
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
}

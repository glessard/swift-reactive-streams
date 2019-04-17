//
//  stream-substream.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import CAtomics

open class SubStream<Value>: EventStream<Value>
{
  private var sub = UnsafeMutablePointer<OpaqueUnmanagedHelper>.allocate(capacity: 1)

  override init(validated: ValidatedQueue)
  {
    CAtomicsInitialize(sub, nil)
    super.init(validated: validated)
  }

  deinit
  {
    let subscription = sub.take()
    subscription?.cancel()
    sub.deallocate()
  }

  open func setSubscription(_ subscription: Subscription)
  {
    assert(CAtomicsLoad(sub, .sequential) == nil, "SubStream cannot subscribe to multiple streams")
    sub.initialize(subscription)
  }

  /// precondition: must run on a barrier block or a serial queue

  override open func finalizeStream()
  {
    let subscription = sub.take()
    subscription?.cancel()
    super.finalizeStream()
  }

  override open func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    let subscription = sub.load()
    subscription?.request(additional)
  }
}

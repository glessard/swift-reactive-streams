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
  private var sub = LockedSubscription()

  public override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  deinit
  {
    let subscription = sub.take()
    subscription?.cancel()
  }

  open func setSubscription(_ subscription: Subscription)
  {
    sub.assign(subscription)
  }

  /// precondition: must run on a barrier block or a serial queue

  override open func finalizeStream()
  {
    let subscription = sub.take()
    subscription?.cancel()
    super.finalizeStream()
  }

  override open func lastSubscriptionWasCanceled()
  {
    super.lastSubscriptionWasCanceled()
    let subscription = sub.load()
    subscription?.requestNone()
  }

  override open func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    let subscription = sub.load()
    subscription?.request(additional)
  }
}

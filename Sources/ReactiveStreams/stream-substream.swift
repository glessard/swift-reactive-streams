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
  private var sub = OpaqueUnmanagedHelper()

  override init(validated: ValidatedQueue)
  {
    sub.initialize(nil)
    super.init(validated: validated)
  }

  deinit
  {
    let subscription = sub.take()
    subscription?.cancel()
  }

  open func setSubscription(_ subscription: Subscription)
  {
    assert(sub.rawLoad(.sequential) == nil, "SubStream cannot subscribe to multiple streams")
    sub.initialize(subscription)
  }

  /// precondition: must run on a barrier block or a serial queue

  override open func finalizeStream()
  {
    let subscription = sub.take()
    subscription?.cancel()
    super.finalizeStream()
  }

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0
    {
      request(additional)
    }
    return additional
  }

  func request(_ additional: Int64)
  {
    let subscription = sub.load()
    subscription?.request(additional)
  }
}

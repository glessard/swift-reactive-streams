//
//  stream-substream.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

open class SubStream<Value>: EventStream<Value>
{
  private var subscription: Subscription? = nil

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  deinit
  {
    subscription?.cancel()
  }

  open func setSubscription(_ subscription: Subscription)
  {
    assert(self.subscription == nil, "SubStream cannot subscribe to multiple streams")
    self.subscription = subscription
  }

  /// precondition: must run on a barrier block or a serial queue

  override open func finalizeStream()
  {
    subscription?.cancel()
    subscription = nil
    super.finalizeStream()
  }

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0
    {
      subscription?.request(additional)
    }
    return additional
  }

  func request(_ additional: Int64)
  {
    subscription?.request(additional)
  }
}

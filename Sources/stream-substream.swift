//
//  stream-substream.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

open class SubStream<InputValue, OutputValue>: Stream<OutputValue>
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
    assert(self.subscription == nil, "SubStream cannot support multiple subscriptions")
    self.subscription = subscription
  }

  /// precondition: must run on a barrier block or a serial queue

  override func finalizeStream()
  {
    self.subscription = nil
    super.finalizeStream()
  }

  /// precondition: must run on a barrier block or a serial queue

  override func performCancellation(_ subscription: Subscription) -> Bool
  {
    if super.performCancellation(subscription)
    { // we have no observers anymore: cancel subscription.
      self.subscription?.cancel()
      self.subscription = nil
      return true
    }
    return false
  }

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    subscription?.request(additional)
    return additional
  }

  open override func close()
  {
    subscription?.cancel()
    subscription = nil
    super.close()
  }
}

open class LimitedStream<InputValue, OutputValue>: SubStream<InputValue, OutputValue>
{
  let limit: Int64
  var count: Int64 = 0

  public convenience init(qos: DispatchQoS = DispatchQoS.current(), count: Int64)
  {
    self.init(validated: ValidatedQueue(qos: qos), count: max(count,0))
  }

  public convenience init(queue: DispatchQueue, count: Int64)
  {
    self.init(validated: ValidatedQueue(queue), count: max(count,0))
  }

  init(validated: ValidatedQueue, count: Int64)
  {
    precondition(count >= 0)
    self.limit = count
    super.init(validated: validated)
  }

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  { // only pass on requested updates up to and including our remaining number of events
    let remaining = (limit-count)
    let adjusted = (remaining > 0) ? min(requested, remaining) : 0
    return super.updateRequest(adjusted)
  }
}

//
//  stream-substream.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public class SubStream<InputValue, OutputValue>: Stream<OutputValue>
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

  public func setSubscription(subscription: Subscription)
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

  override func performCancellation(subscription: Subscription) -> Bool
  {
    if super.performCancellation(subscription)
    { // we have no observers anymore: cancel subscription.
      self.subscription?.cancel()
      self.subscription = nil
      return true
    }
    return false
  }

  public override func updateRequest(requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0
    {
      subscription?.request(additional)
    }
    return additional
  }

  public override func close()
  {
    subscription?.cancel()
    subscription = nil
    super.close()
  }
}

public class SerialSubStream<InputValue, OutputValue>: SubStream<InputValue, OutputValue>
{
  public convenience init(qos: qos_class_t = qos_class_self())
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true))
  }

  public convenience init(queue: dispatch_queue_t)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: true))
  }

  override init(validated: ValidatedQueue)
  {
    switch validated.queue
    {
    case .serial:
      super.init(validated: validated)
    case .concurrent(let queue):
      super.init(validated: ValidatedQueue(queue: queue, serial: true))
    }
  }

  /// precondition: must run on this stream's serial queue

  override func dispatch(result: Result<OutputValue>)
  {
    guard requested != Int64.min else { return }

    switch result
    {
    case .value: dispatchValue(result)
    case .error: dispatchError(result)
    }
  }
}

public class LimitedStream<InputValue, OutputValue>: SerialSubStream<InputValue, OutputValue>
{
  let limit: Int64
  var count: Int64 = 0

  public convenience init(qos: qos_class_t = qos_class_self(), count: Int64)
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true), count: max(count,0))
  }

  public convenience init(queue: dispatch_queue_t, count: Int64)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: true), count: max(count,0))
  }

  init(validated: ValidatedQueue, count: Int64)
  {
    precondition(count >= 0)
    self.limit = count
    super.init(validated: validated)
  }

  public override func updateRequest(requested: Int64) -> Int64
  { // only pass on requested updates up to and including our remaining number of events
    let remaining = (limit-count)
    let adjusted = (remaining > 0) ? min(requested, remaining) : 0
    return super.updateRequest(adjusted)
  }
}

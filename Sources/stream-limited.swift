//
//  stream-limited.swift
//  stream
//
//  Created by Guillaume Lessard on 4/28/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

open class LimitedStream<InputValue, OutputValue>: SubStream<InputValue, OutputValue>
{
  let limit: Int64
  var count: Int64 = 0

  public convenience init(qos: DispatchQoS = DispatchQoS.current(), count: Int64)
  {
    self.init(validated: ValidatedQueue(qos: qos), count: max(count,0))
  }

  public convenience init(_ queue: DispatchQueue, count: Int64)
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
    precondition(requested > 0)

    let remaining = (limit-count)
    let adjusted = min(requested, remaining)
    if adjusted > 0
    {
      return super.updateRequest(adjusted)
    }
    return 0
  }
}

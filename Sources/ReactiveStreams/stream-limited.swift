//
//  stream-limited.swift
//  stream
//
//  Created by Guillaume Lessard on 4/28/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics
import Outcome

open class LimitedStream<InputValue, OutputValue>: SubStream<InputValue, OutputValue>
{
  public let limit: Int64
  private var counter = AtomicInt64()
  public var count: Int64 { return counter.load(.relaxed) }

  public convenience init(qos: DispatchQoS = DispatchQoS.current, count: Int64)
  {
    self.init(validated: ValidatedQueue(label: "limitedstream", qos: qos), count: max(count,0))
  }

  public convenience init(_ queue: DispatchQueue, count: Int64)
  {
    self.init(validated: ValidatedQueue(label: "limitedstream", target: queue), count: max(count,0))
  }

  init(validated: ValidatedQueue, count: Int64)
  {
    assert(count >= 0)
    counter.initialize(0)
    self.limit = count
    super.init(validated: validated)
  }

  open override func dispatch(_ event: Outcome<OutputValue>)
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    guard count < limit else { return }

    super.dispatch(event)
    let c = 1+counter.fetch_add(1, .relaxed)
    if c == limit && event.isValue
    { // close the stream if it hasn't been closed already
      super.dispatch(Event.streamCompleted)
    }
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

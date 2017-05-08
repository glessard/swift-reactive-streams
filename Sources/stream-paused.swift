//
//  stream-paused.swift
//  stream
//
//  Created by Guillaume Lessard on 4/26/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

open class Paused<Value>: SubStream<Value, Value>
{
  private var torequest = Int64(0)
  private var started = false

  public init(_ stream: EventStream<Value>)
  {
    super.init(validated: ValidatedQueue(label: "pausedrequests", target: stream.queue))

    stream.subscribe(
      substream: self,
      notificationHandler: {
        substream, result in
        // already running on substream.queue
        substream.dispatch(result)
      }
    )
  }

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  {
    if started
    {
      return super.updateRequest(requested)
    }

    precondition(requested > 0)

    var p = torequest
    assert(p >= 0)
    while p != Int64.max
    {
      let tentatively = p &+ requested // could overflow; avoid trapping
      let updatedRequest = tentatively > 0 ? tentatively : Int64.max
      if OSAtomicCompareAndSwap64(p, updatedRequest, &torequest)
      {
        return updatedRequest
      }
      p = torequest
    }
    return Int64.max
  }

  open func start()
  {
    if (!started)
    {
      started = true
      var p = torequest
      while  !OSAtomicCompareAndSwap64(p, 0, &torequest)
      {
        p = torequest
      }

      super.updateRequest(p)
    }
  }
}

extension EventStream
{
  public func paused() -> Paused<Value>
  {
    return Paused(self)
  }
}

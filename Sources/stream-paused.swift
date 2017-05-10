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

    var prev, updated: Int64
    repeat {
      prev = torequest
      if prev == Int64.max { return Int64.max }
      let tentatively = prev &+ requested  // could overflow; avoid trapping
      updated = tentatively > 0 ? tentatively : Int64.max
    } while !OSAtomicCompareAndSwap64(prev, updated, &torequest)

    return updated
  }

  open func start()
  {
    if (!started)
    {
      started = true
      var prev: Int64
      repeat { // atomic swap would be better here
        prev = torequest
      } while !OSAtomicCompareAndSwap64(prev, 0, &torequest)

      super.updateRequest(prev)
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

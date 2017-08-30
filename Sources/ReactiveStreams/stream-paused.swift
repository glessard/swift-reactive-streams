//
//  stream-paused.swift
//  stream
//
//  Created by Guillaume Lessard on 4/26/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import CAtomics

open class Paused<Value>: SubStream<Value, Value>
{
  private var torequest = CAtomicsInt64()
  private var started = CAtomicsBoolean()

  public init(_ stream: EventStream<Value>)
  {
    CAtomicsInt64Init(0, &torequest)
    CAtomicsBooleanInit(false, &started)
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
    if CAtomicsBooleanLoad(&started, .relaxed)
    {
      return super.updateRequest(requested)
    }

    precondition(requested > 0)

    var updated: Int64
    var current = CAtomicsInt64Load(&torequest, .relaxed)
    repeat {
      if current == Int64.max { return Int64.max }
      let tentatively = current &+ requested  // could overflow; avoid trapping
      updated = tentatively > 0 ? tentatively : Int64.max
    } while !CAtomicsInt64CAS(&current, updated, &torequest, .weak, .relaxed, .relaxed)

    return updated
  }

  open func start()
  {
    var f = false
    if CAtomicsBooleanCAS(&f, true, &started, .strong, .relaxed, .relaxed)
    {
      let request = CAtomicsInt64Swap(0, &torequest, .relaxed)
      super.updateRequest(request)
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

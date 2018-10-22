//
//  stream-paused.swift
//  stream
//
//  Created by Guillaume Lessard on 4/26/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import CAtomics

open class Paused<Value>: SubStream<Value>
{
  private var torequest = AtomicInt64()
  private var started = AtomicBool()

  public init(_ stream: EventStream<Value>)
  {
    torequest.initialize(0)
    started.initialize(false)
    super.init(validated: ValidatedQueue(label: "pausedrequests", target: stream.queue))

    stream.subscribe(substream: self)
  }

  open override func updateRequest(_ requested: Int64)
  {
    if started.load(.relaxed) == true
    {
      super.updateRequest(requested)
      return
    }

    precondition(requested > 0)

    var updated: Int64
    var current = torequest.load(.relaxed)
    repeat {
      if current == .max { return }
      updated = current &+ requested // could overflow; avoid trapping
      if updated < 0 { updated = .max } // check and correct for overflow
    } while !torequest.loadCAS(&current, updated, .weak, .relaxed, .relaxed)
  }

  open func start()
  {
    var streaming = started.load(.relaxed)
    repeat {
      if streaming { return }
    } while !started.loadCAS(&streaming, true, .weak, .relaxed, .relaxed)

    let request = torequest.swap(0, .relaxed)
    if request > 0 { super.updateRequest(request) }
  }
}

extension EventStream
{
  public func paused() -> Paused<Value>
  {
    return Paused(self)
  }
}

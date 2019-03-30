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
  private var pending = AtomicInt64()

  public init(_ stream: EventStream<Value>)
  {
    CAtomicsInitialize(&pending, 0)
    super.init(validated: ValidatedQueue(label: "pausedrequests", target: stream.queue))

    stream.subscribe(substream: self)
  }

  open override func updateRequest(_ requested: Int64)
  {
    precondition(requested > 0)

    var updated: Int64
    var request = CAtomicsLoad(&pending, .relaxed)
    repeat {
      if request == .min
      {
        super.updateRequest(requested)
        return
      }
      if request == .max { return }
      updated = request &+ requested // could overflow; avoid trapping
      if updated < 0 { updated = .max } // check and correct for overflow
    } while !CAtomicsCompareAndExchange(&pending, &request, updated, .weak, .relaxed, .relaxed)
  }

  open func start()
  {
    var request = CAtomicsLoad(&pending, .relaxed)
    repeat {
      if request == .min { return }
    } while !CAtomicsCompareAndExchange(&pending, &request, .min, .weak, .relaxed, .relaxed)

    if request > 0 { super.updateRequest(request) }
  }

  public var isPaused: Bool {
    return CAtomicsLoad(&pending, .relaxed) != .min
  }
}

extension EventStream
{
  public func paused() -> Paused<Value>
  {
    return Paused(self)
  }
}

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

  public init(_ stream: Stream<Value>)
  {
    super.init(validated: ValidatedQueue(stream.queue))

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

    torequest += requested
    return torequest
  }

  open func start()
  {
    if (!started)
    {
      started = true
      if torequest > 0
      {
        super.updateRequest(torequest)
        torequest = 0
      }
    }
  }
}

extension Stream
{
  public func paused() -> Paused<Value>
  {
    return Paused(self)
  }
}

//
//  stream-next.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  public func next(qos: DispatchQoS? = nil, count: Int) -> EventStream<Value>
  {
    let stream = LimitedStream<Value>(qos: qos ?? self.qos, count: Int64(count))
    self.subscribe(substream: stream)
    return stream
  }

  public func next(queue: DispatchQueue, count: Int) -> EventStream<Value>
  {
    let stream = LimitedStream<Value>(queue: queue, count: Int64(count))
    self.subscribe(substream: stream)
    return stream
  }
}

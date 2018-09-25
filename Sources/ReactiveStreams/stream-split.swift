//
//  stream-split.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  public func split(qos: DispatchQoS? = nil) -> (EventStream, EventStream)
  {
    let streams = self.split(qos: qos, count: 2)
    return (streams[0], streams[1])
  }

  public func split(qos: DispatchQoS? = nil, count: Int) -> [EventStream]
  {
    precondition(count >= 0)
    guard count > 0 else { return [EventStream]() }

    let streams = (0..<count).map {
      _ -> EventStream in
      let stream = SubStream<Value, Value>(qos: qos ?? self.qos)
      self.subscribe(substream: stream)
      return stream
    }
    return streams
  }
}

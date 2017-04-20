//
//  stream-split.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension Stream
{
  public func split(qos: DispatchQoS = DispatchQoS.current()) -> (Stream, Stream)
  {
    let streams = self.split(qos: qos, count: 2)
    return (streams[0], streams[1])
  }

  public func split(qos: DispatchQoS = DispatchQoS.current(), count: Int) -> [Stream]
  {
    precondition(count >= 0)
    guard count > 0 else { return [Stream]() }

    let streams = (0..<count).map {
      _ -> Stream in
      let stream = SubStream<Value, Value>(qos: qos)
      self.subscribe(substream: stream) {
        mapped, result in
        mapped.queue.async { mapped.dispatch(result) }
      }
      return stream
    }
    return streams
  }
}

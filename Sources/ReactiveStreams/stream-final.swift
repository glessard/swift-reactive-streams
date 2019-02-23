//
//  stream-final.swift
//  stream
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func finalValue(_ stream: SingleValueStream<Value, Value>) -> EventStream<Value>
  {
    var latest: Event<Value>? = nil
    self.subscribe(substream: stream) {
      mapped, event in
      if event.isValue
      {
        latest = event
      }
      else
      {
        mapped.queue.async {
          latest.map({ mapped.dispatch($0) })
          mapped.dispatch(event)
        }
      }
    }
    return stream
  }

  public func finalValue(qos: DispatchQoS? = nil) -> EventStream<Value>
  {
    return finalValue(SingleValueStream<Value, Value>(qos: qos ?? self.qos))
  }

  public func finalValue(queue: DispatchQueue) -> EventStream<Value>
  {
    return finalValue(SingleValueStream<Value, Value>(queue: queue))
  }
}

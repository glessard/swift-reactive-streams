//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func map<U>(_ stream: SubStream<Value, U>, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, event in
      mapped.queue.async { mapped.dispatch(event.map(transform)) }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<Value, U>(qos: qos ?? self.qos), transform: transform)
  }

  public func map<U>(_ queue: DispatchQueue, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<Value, U>(queue), transform: transform)
  }
}

extension EventStream
{
  private func map<U>(_ stream: SubStream<Value, U>, transform: @escaping (Value) -> Event<U>) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, event in
      mapped.queue.async { mapped.dispatch(event.flatMap(transform)) }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) -> Event<U>) -> EventStream<U>
  {
    return map(SubStream<Value, U>(qos: qos ?? self.qos), transform: transform)
  }

  public func map<U>(_ queue: DispatchQueue, transform: @escaping (Value) -> Event<U>) -> EventStream<U>
  {
    return map(SubStream<Value, U>(queue), transform: transform)
  }
}

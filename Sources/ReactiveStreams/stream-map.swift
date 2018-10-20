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
  private func map<U>(_ stream: SubStream<U>, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, event in
      mapped.queue.async {
        do {
          let transformed = try transform(event.get())
          mapped.dispatch(Event(value: transformed))
        }
        catch {
          mapped.dispatch(Event(error: error))
        }
      }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<U>(qos: qos ?? self.qos), transform: transform)
  }

  public func map<U>(queue: DispatchQueue, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<U>(queue: queue), transform: transform)
  }
}

extension EventStream
{
  private func map<U>(_ stream: SubStream<U>, transform: @escaping (Value) throws -> Event<U>) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, event in
      mapped.queue.async {
        do {
          let transformed = try transform(event.get())
          mapped.dispatch(transformed)
        }
        catch {
          mapped.dispatch(Event(error: error))
        }
      }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) throws -> Event<U>) -> EventStream<U>
  {
    return map(SubStream<U>(qos: qos ?? self.qos), transform: transform)
  }

  public func map<U>(queue: DispatchQueue, transform: @escaping (Value) throws -> Event<U>) -> EventStream<U>
  {
    return map(SubStream<U>(queue: queue), transform: transform)
  }
}

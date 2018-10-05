//
//  stream-filter.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/25/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func compactMap<U>(_ stream: SubStream<U>, transform: @escaping (Value) throws -> U?) -> EventStream<U>
  {
    self.subscribe(
      substream: stream,
      notificationHandler: {
        mapped, event in
        mapped.queue.async {
          do {
            if let transformed = try transform(event.get())
            {
              mapped.dispatch(Event(value: transformed))
            }
            else
            {
              mapped.request(1)
            }
          }
          catch {
            mapped.dispatch(Event(error: error))
          }
        }
      }
    )
    return stream
  }

  public func compactMap<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) throws -> U?) -> EventStream<U>
  {
    return compactMap(SubStream(qos: qos ?? self.qos), transform: transform)
  }

  public func compactMap<U>(_ queue: DispatchQueue, transform: @escaping (Value) throws -> U?) -> EventStream<U>
  {
    return compactMap(SubStream(queue), transform: transform)
  }
}

extension EventStream
{
  public func filter(qos: DispatchQoS? = nil, predicate: @escaping (Value) throws -> Bool) -> EventStream<Value>
  {
    return compactMap(qos: qos, transform: { try predicate($0) ? $0 : nil })
  }

  public func filter(_ queue: DispatchQueue, predicate: @escaping (Value) throws -> Bool) -> EventStream<Value>
  {
    return compactMap(queue, transform: { try predicate($0) ? $0 : nil })
  }
}

extension EventStream
{
  public func compacted<U>() -> EventStream<U>
    where Value == Optional<U>
  {
    return compacted(self.queue)
  }

  public func compacted<U>(qos: DispatchQoS) -> EventStream<U>
    where Value == Optional<U>
  {
    return compactMap(qos: qos, transform: { $0 })
  }

  public func compacted<U>(_ queue: DispatchQueue) -> EventStream<U>
    where Value == Optional<U>
  {
    return compactMap(queue, transform: { $0 })
  }
}

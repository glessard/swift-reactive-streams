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
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, subscription, event in
        let newEvent: Event<U>
        do {
          guard let transformed = try transform(event.get())
          else {
            subscription.request(1)
            return
          }
          newEvent = Event(value: transformed)
        }
        catch {
          newEvent = Event(error: error)
        }
        mapped.queue.async { mapped.dispatch(newEvent) }
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
    return compactMap(SubStream(queue: queue), transform: transform)
  }
}

extension EventStream
{
  public func filter(qos: DispatchQoS? = nil, predicate: @escaping (Value) throws -> Bool) -> EventStream<Value>
  {
    return compactMap(qos: qos, transform: { try predicate($0) ? $0 : nil })
  }

  public func filter(queue: DispatchQueue, predicate: @escaping (Value) throws -> Bool) -> EventStream<Value>
  {
    return compactMap(queue, transform: { try predicate($0) ? $0 : nil })
  }
}

extension EventStream
{
  private func compact<U>(_ stream: SubStream<U>) -> EventStream<U>
    where Value == Optional<U>
  {
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, subscription, event in
        let newEvent: Event<U>
        do {
          guard let value = try event.get()
          else {
            subscription.request(1)
            return
          }
          newEvent = Event(value: value)
        }
        catch {
          newEvent = Event(error: error)
        }
        mapped.queue.async { mapped.dispatch(newEvent) }
      }
    )
    return stream
  }

  public func compact<U>(qos: DispatchQoS? = nil) -> EventStream<U>
    where Value == Optional<U>
  {
    return compact(SubStream(qos: qos ?? self.qos))
  }

  public func compact<U>(queue: DispatchQueue) -> EventStream<U>
    where Value == Optional<U>
  {
    return compact(SubStream(queue: queue))
  }
}

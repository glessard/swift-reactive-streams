//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension EventStream
{
  private func map<U>(_ stream: SubStream<Value, U>, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, result in
      mapped.queue.async { mapped.dispatch(result.map(transform)) }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS = DispatchQoS.current(), transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<Value, U>(qos: qos), transform: transform)
  }

  public func map<U>(_ queue: DispatchQueue, transform: @escaping (Value) throws -> U) -> EventStream<U>
  {
    return map(SubStream<Value, U>(queue), transform: transform)
  }
}

extension EventStream
{
  private func map<U>(_ stream: SubStream<Value, U>, transform: @escaping (Value) -> Result<U>) -> EventStream<U>
  {
    self.subscribe(substream: stream) {
      mapped, result in
      mapped.queue.async { mapped.dispatch(result.flatMap(transform)) }
    }
    return stream
  }

  public func map<U>(qos: DispatchQoS = DispatchQoS.current(), transform: @escaping (Value) -> Result<U>) -> EventStream<U>
  {
    return map(SubStream<Value, U>(qos: qos), transform: transform)
  }

  public func map<U>(_ queue: DispatchQueue, transform: @escaping (Value) -> Result<U>) -> EventStream<U>
  {
    return map(SubStream<Value, U>(queue), transform: transform)
  }
}

extension EventStream
{
  private func flatMap<U>(_ stream: MergeStream<U>, transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        merged, result in
        merged.queue.async {
          switch result
          {
          case .value(let value):
            merged.performMerge(transform(value))
          case .error(_ as StreamCompleted):
            merged.close()
          case .error(let error):
            merged.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func flatMap<U>(qos: DispatchQoS = DispatchQoS.current(), transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    return flatMap(MergeStream(qos: qos), transform: transform)
  }

  public func flatMap<U>(_ queue: DispatchQueue, transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    return flatMap(MergeStream(queue), transform: transform)
  }
}

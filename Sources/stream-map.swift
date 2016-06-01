//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension Stream
{
  private func map<U>(stream: SubStream<Value, U>, transform: (Value) throws -> U) -> Stream<U>
  {
    self.subscribe(substream: stream) {
      mapped, result in
      dispatch_async(mapped.queue) { mapped.dispatch(result.map(transform)) }
    }
    return stream
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<Value, U>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<Value, U>(queue: queue), transform: transform)
  }
}

extension Stream
{
  private func map<U>(stream: SubStream<Value, U>, transform: (Value) -> Result<U>) -> Stream<U>
  {
    self.subscribe(substream: stream) {
      mapped, result in
      dispatch_async(mapped.queue) { mapped.dispatch(result.flatMap(transform)) }
    }
    return stream
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<Value, U>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Value) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<Value, U>(queue: queue), transform: transform)
  }
}

extension Stream
{
  private func flatMap<U>(stream: MergeStream<U>, transform: (Value) -> Stream<U>) -> Stream<U>
  {
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        merged, result in
        dispatch_async(merged.queue) {
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

  public func flatMap<U>(queue queue: dispatch_queue_t, transform: (Value) -> Stream<U>) -> Stream<U>
  {
    return flatMap(MergeStream(queue: queue), transform: transform)
  }

  public func flatMap<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) -> Stream<U>) -> Stream<U>
  {
    return flatMap(MergeStream(qos: qos), transform: transform)
  }
}

//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class SubStream<Value, SourceValue>: Stream<Value>
{
  private var source: Subscription? = nil

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  public func setSubscription(subscription: Subscription)
  {
    assert(source == nil, "SubStream cannot support multiple subscriptions")
    source = subscription
  }

  /// precondition: must run on a barrier block or a serial queue

  override func finalizeStream()
  {
    self.source = nil
    super.finalizeStream()
  }

  public override func updateRequest(requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0, let source = source
    {
      source.request(additional)
    }
    return additional
  }

  public override func close()
  {
    if let source = source { source.cancel() }
    super.close()
  }
}

public class SerialSubStream<Value, SourceValue>: SubStream<Value, SourceValue>
{
  public convenience init(qos: qos_class_t = qos_class_self())
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true))
  }

  public convenience init(queue: dispatch_queue_t)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: true))
  }

  override init(validated: ValidatedQueue)
  {
    switch validated.queue
    {
    case .serial:
      super.init(validated: validated)
    case .concurrent(let queue):
      super.init(validated: ValidatedQueue(queue: queue, serial: true))
    }
  }
}

public class LimitedStream<Value, SourceValue>: SerialSubStream<Value, SourceValue>
{
  let limit: Int64
  var count: Int64 = 0

  public convenience init(qos: qos_class_t = qos_class_self(), count: Int64)
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true), count: max(count,0))
  }

  public convenience init(queue: dispatch_queue_t, count: Int64)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: true), count: max(count,0))
  }

  init(validated: ValidatedQueue, count: Int64)
  {
    precondition(count >= 0)
    self.limit = count
    super.init(validated: validated)
  }

  public override func updateRequest(requested: Int64) -> Int64
  { // only pass on requested updates up to and including our remaining number of events
    let remaining = (limit-count)
    let adjusted = (remaining > 0) ? min(requested, remaining) : 0
    return super.updateRequest(adjusted)
  }
}

extension Stream
{
  private func map<U>(mapped: SubStream<U, Value>, transform: (Value) throws -> U) -> Stream<U>
  {
    self.subscribe(mapped) { result in mapped.process { result.map(transform) } }
    return mapped
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<U, Value>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<U, Value>(queue: queue), transform: transform)
  }
}

extension Stream
{
  private func map<U>(mapped: SubStream<U, Value>, transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    self.subscribe(mapped) { result in mapped.process { transform(result) } }
    return mapped
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<U, Value>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<U, Value>(queue: queue), transform: transform)
  }
}

extension Stream
{
  public func notify(qos qos: qos_class_t = qos_class_self(), task: (Result<Value>) -> Void)
  {
    notify(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify(queue queue: dispatch_queue_t, task: (Result<Value>) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)

    self.subscribe({ $0.requestAll() }) {
      result in
      dispatch_async(local) { task(result) }
    }
  }
}

extension Stream
{
  public func onValue(qos qos: qos_class_t = qos_class_self(), task: (Value) -> Void)
  {
    onValue(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onValue(queue queue: dispatch_queue_t, task: (Value) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)

    self.subscribe({ $0.requestAll() }) {
      result in
      if case .value(let value) = result
      {
        dispatch_async(local) { task(value) }
      }
    }
  }
}

extension Stream
{
  public func onError(qos qos: qos_class_t = qos_class_self(), task: (ErrorType) -> Void)
  {
    onError(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onError(queue queue: dispatch_queue_t, task: (ErrorType) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.subscribe({ _ in }) {
      result in
      if case .error(let error) = result
      {
        dispatch_async(local) { task(error) }
      }
    }
  }
}

extension Stream
{
  public func onCompletion(qos qos: qos_class_t = qos_class_self(), task: (StreamCompleted) -> Void)
  {
    onCompletion(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onCompletion(queue queue: dispatch_queue_t, task: (StreamCompleted) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.subscribe({ _ in }) {
      result in
      if case .error(let status as StreamCompleted) = result
      {
        dispatch_async(local) { task(status) }
      }
    }
  }
}

extension Stream
{
  private func next(mapped: LimitedStream<Value, Value>) -> Stream<Value>
  {
    let limit = mapped.limit
    self.subscribe(mapped.setSubscription) {
      result in
      mapped.process {
        switch mapped.count+1
        {
        case let c where c < limit:
          mapped.count = c
          return result
        case limit:
          mapped.count = limit
          mapped.process(result)
          mapped.process(StreamCompleted.terminated)
          return nil
        default:
          return nil
        }
      }
    }
    return mapped
  }

  public func next(qos qos: qos_class_t = qos_class_self(), count: Int = 1) -> Stream<Value>
  {
    return next(LimitedStream<Value, Value>(qos: qos, count: Int64(max(count, 0))))
  }

  public func next(queue queue: dispatch_queue_t, count: Int = 1) -> Stream<Value>
  {
    return next(LimitedStream<Value, Value>(queue: queue, count: Int64(max(count, 0))))
  }
}

extension Stream
{
  private func final(mapped: LimitedStream<Value, Value>) -> Stream<Value>
  {
    var last: Value? = nil
    self.subscribe({
        subscription in
        subscription.requestAll()
        mapped.setSubscription(subscription)
      },
      notificationHandler: {
        result in
        mapped.process {
          switch result
          {
          case .value(let value):
            last = value
          case .error:
            if let value = last { mapped.process(value) }
            mapped.process(result)
          }
          return nil
        }
      }
    )
    return mapped
  }

  public func final(qos qos: qos_class_t = qos_class_self()) -> Stream<Value>
  {
    return final(LimitedStream<Value, Value>(qos: qos, count: 1))
  }

  public func final(queue queue: dispatch_queue_t) -> Stream<Value>
  {
    return final(LimitedStream<Value, Value>(queue: queue, count: 1))
  }
}

extension Stream
{
  private func reduce<U>(mapped: LimitedStream<U, Value>, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    var current = initial
    self.subscribe({
        subscription in
        subscription.requestAll()
        mapped.setSubscription(subscription)
      },
      notificationHandler: {
        result in
        mapped.process {
          switch result
          {
          case .value(let value):
            do {
              current = try transform(current, value)
            }
            catch {
              mapped.process(current)
              mapped.process(error)
            }
          case .error(let error):
            mapped.process(current)
            mapped.process(error)
          }
          return nil
        }
      }
    )
    return mapped
  }

  public func reduce<U>(initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<U, Value>(qos: qos_class_self(), count: 1), initial: initial, transform: transform)
  }

  public func reduce<U>(qos qos: qos_class_t, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<U, Value>(qos: qos, count: 1), initial: initial, transform: transform)
  }

  public func reduce<U>(queue queue: dispatch_queue_t, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<U, Value>(queue: queue, count: 1), initial: initial, transform: transform)
  }
}

extension Stream
{
  private func countEvents(mapped: LimitedStream<Int, Value>) -> Stream<Int>
  {
    var total = 0
    self.subscribe({
        subscription in
        mapped.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        result in
        mapped.process {
          switch result
          {
          case .value:
            total += 1
          case .error(let error):
            mapped.process(total)
            mapped.process(error)
          }
          return nil
        }
      }
    )
    return mapped
  }

  public func countEvents(qos qos: qos_class_t = qos_class_self()) -> Stream<Int>
  {
    return countEvents(LimitedStream<Int, Value>(qos: qos, count: 1))
  }

  public func countEvents(queue queue: dispatch_queue_t) -> Stream<Int>
  {
    return countEvents(LimitedStream<Int, Value>(queue: queue, count: 1))
  }
}

extension Stream
{
  private func coalesce(mapped: LimitedStream<[Value], Value>) -> Stream<[Value]>
  {
    var current = [Value]()
    self.subscribe({
        subscription in
        mapped.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        result in
        mapped.process {
          switch result
          {
          case .value(let value):
            current.append(value)
          case .error(let error):
            mapped.process(current)
            mapped.process(error)
          }
          return nil
        }
      }
    )
    return mapped
  }

  public func coalesce(qos qos: qos_class_t = qos_class_self()) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<[Value], Value>(qos: qos, count: 1))
  }

  public func coalesce(queue queue: dispatch_queue_t) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<[Value], Value>(queue: queue, count: 1))
  }
}

extension Stream
{
  public func split(qos qos: qos_class_t = qos_class_self()) -> (Stream, Stream)
  {
    let streams = self.split(qos: qos, count: 2)
    return (streams[0], streams[1])
  }

  public func split(qos qos: qos_class_t = qos_class_self(), count: Int) -> [Stream]
  {
    precondition(count >= 0)
    guard count > 0 else { return [Stream]() }

    let streams = (0..<count).map {
      _ -> Stream in
      let stream = SubStream<Value, Value>(qos: qos)
      self.subscribe(stream, notificationHandler: stream.process)
      return stream
    }
    return streams
  }
}

extension Stream
{
  private func flatMap<U>(merged: MergeStream<U>, transform: (Value) -> Stream<U>) -> Stream<U>
  {
    self.subscribe(merged.setSubscription) {
      result in
      merged.process {
        switch result
        {
        case .value(let value):
          merged.merge(transform(value))
        case .error(_ as StreamCompleted):
          merged.close()
        case .error(let error):
          merged.process(error)
        }
        return nil
      }
    }
    return merged
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

//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class SubStream<InputValue, OutputValue>: Stream<OutputValue>
{
  private var subscription: Subscription? = nil

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  deinit
  {
    if let subscription = subscription { subscription.cancel() }
  }

  public func setSubscription(subscription: Subscription)
  {
    assert(self.subscription == nil, "SubStream cannot support multiple subscriptions")
    self.subscription = subscription
  }

  /// precondition: must run on a barrier block or a serial queue

  override func finalizeStream()
  {
    self.subscription = nil
    super.finalizeStream()
  }

  /// precondition: must run on a barrier block or a serial queue

  override func performCancellation(subscription: Subscription) -> Bool
  {
    if super.performCancellation(subscription)
    {
      if let sub = self.subscription
      { // we have no observers anymore: cancel subscription.
        sub.cancel()
        self.subscription = nil
      }
      return true
    }
    return false
  }

  public override func updateRequest(requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0, let subscription = subscription
    {
      subscription.request(additional)
    }
    return additional
  }

  public override func close()
  {
    if let subscription = subscription
    {
      subscription.cancel()
      self.subscription = nil
    }
    super.close()
  }
}

public class SerialSubStream<InputValue, OutputValue>: SubStream<InputValue, OutputValue>
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

  /// precondition: must run on this stream's serial queue

  override func dispatch(result: Result<OutputValue>)
  {
    guard requested != Int64.min else { return }

    switch result
    {
    case .value: dispatchValue(result)
    case .error: dispatchError(result)
    }
  }
}

public class LimitedStream<InputValue, OutputValue>: SerialSubStream<InputValue, OutputValue>
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
  private func map<U>(stream: SubStream<Value, U>, transform: (Value) throws -> U) -> Stream<U>
  {
    self.subscribe(substream: stream) { mapped, result in mapped.process(result.map(transform)) }
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
    self.subscribe(substream: stream) { mapped, result in mapped.process(result.flatMap(transform)) }
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
  private func performNotify(queue queue: dispatch_queue_t, task: (Result<Value>) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        q, result in
        assert(q === queue)
        dispatch_async(queue) { task(result) }
      }
    )
  }

  public func notify(qos qos: qos_class_t = qos_class_self(), task: (Result<Value>) -> Void)
  {
    let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)
    performNotify(queue: dispatch_queue_create("local-notify-queue", attr), task: task)
  }

  public func notify(queue queue: dispatch_queue_t, task: (Result<Value>) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    performNotify(queue: local, task: task)
  }
}

extension Stream
{
  private func performOnValue(queue queue: dispatch_queue_t, task: (Value) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .value(let value) = result
        {
          dispatch_async(queue) { task(value) }
        }
      }
    )
  }

  public func onValue(qos qos: qos_class_t = qos_class_self(), task: (Value) -> Void)
  {
    let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)
    performOnValue(queue: dispatch_queue_create("local-notify-queue", attr), task: task)
  }

  public func onValue(queue queue: dispatch_queue_t, task: (Value) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    performOnValue(queue: local, task: task)
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

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .error(let error) = result
        {
          dispatch_async(local) { task(error) }
        }
      }
    )
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

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .error(let status as StreamCompleted) = result
        {
          dispatch_async(local) { task(status) }
        }
      }
    )
  }
}

extension Stream
{
  private func next(stream: LimitedStream<Value, Value>) -> Stream<Value>
  {
    let limit = stream.limit
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch mapped.count+1
          {
          case let c where c < limit:
            mapped.count = c
            mapped.dispatchValue(result)
          case limit:
            mapped.count = limit
            mapped.dispatchValue(result)
            mapped.close()
          default:
            break
          }
          return
        }
      }
    )
    return stream
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
  private func final(stream: LimitedStream<Value, Value>) -> Stream<Value>
  {
    var last: Value? = nil
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        subscription.requestAll()
        stream.setSubscription(subscription)
      },
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value(let value):
            last = value
          case .error:
            if let value = last { mapped.dispatchValue(Result.value(value)) }
            mapped.dispatchError(result)
          }
        }
      }
    )
    return stream
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
  private func reduce<U>(stream: LimitedStream<Value, U>, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    var current = initial
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        subscription.requestAll()
        stream.setSubscription(subscription)
      },
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value(let value):
            do {
              current = try combine(current, value)
            }
            catch {
              mapped.dispatchValue(Result.value(current))
              mapped.dispatchError(Result.error(error))
            }
          case .error(let error):
            mapped.dispatchValue(Result.value(current))
            mapped.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func reduce<U>(initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos_class_self(), count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(qos qos: qos_class_t, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(qos: qos, count: 1), initial: initial, combine: combine)
  }

  public func reduce<U>(queue queue: dispatch_queue_t, initial: U, combine: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(LimitedStream<Value, U>(queue: queue, count: 1), initial: initial, combine: combine)
  }
}

extension Stream
{
  private func countEvents(stream: LimitedStream<Value, Int>) -> Stream<Int>
  {
    var total = 0
    self.subscribe(subscriber: stream,
      subscriptionHandler: {
        subscription in
        stream.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value:
            total += 1
          case .error(let error):
            mapped.dispatchValue(Result.value(total))
            mapped.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func countEvents(qos qos: qos_class_t = qos_class_self()) -> Stream<Int>
  {
    return countEvents(LimitedStream<Value, Int>(qos: qos, count: 1))
  }

  public func countEvents(queue queue: dispatch_queue_t) -> Stream<Int>
  {
    return countEvents(LimitedStream<Value, Int>(queue: queue, count: 1))
  }
}

extension Stream
{
  private func coalesce(stream: LimitedStream<Value, [Value]>) -> Stream<[Value]>
  {
    var current = [Value]()
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: {
        subscription in
        stream.setSubscription(subscription)
        subscription.requestAll()
      },
      notificationHandler: {
        mapped, result in
        dispatch_async(mapped.queue) {
          switch result
          {
          case .value(let value):
            current.append(value)
          case .error(let error):
            mapped.dispatchValue(Result.value(current))
            mapped.dispatchError(Result.error(error))
          }
        }
      }
    )
    return stream
  }

  public func coalesce(qos qos: qos_class_t = qos_class_self()) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<Value, [Value]>(qos: qos, count: 1))
  }

  public func coalesce(queue queue: dispatch_queue_t) -> Stream<[Value]>
  {
    return coalesce(LimitedStream<Value, [Value]>(queue: queue, count: 1))
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
      self.subscribe(substream: stream) { mapped, result in mapped.process(result) }
      return stream
    }
    return streams
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

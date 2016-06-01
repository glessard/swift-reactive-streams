//
//  stream-notifications.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

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

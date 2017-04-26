//
//  stream-notifications.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension Stream
{
  private func performNotify(queue: DispatchQueue, task: @escaping (Result<Value>) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        q, result in
        assert(q === queue)
        queue.async { task(result) }
      }
    )
  }

  public func notify(qos: DispatchQoS = DispatchQoS.current(), task: @escaping (Result<Value>) -> Void)
  {
    performNotify(queue: DispatchQueue(label: "local-notify-queue", qos: qos), task: task)
  }

  public func notify(queue: DispatchQueue, task: @escaping (Result<Value>) -> Void)
  {
    performNotify(queue: DispatchQueue(label: "local-notify-queue", target: queue), task: task)
  }
}

extension Stream
{
  private func performOnValue(queue: DispatchQueue, task: @escaping (Value) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .value(let value) = result
        {
          queue.async { task(value) }
        }
      }
    )
  }

  public func onValue(qos: DispatchQoS = DispatchQoS.current(), task: @escaping (Value) -> Void)
  {
    performOnValue(queue: DispatchQueue(label: "local-notify-queue", qos: qos), task: task)
  }

  public func onValue(queue: DispatchQueue, task: @escaping (Value) -> Void)
  {
    performOnValue(queue: DispatchQueue(label: "local-notify-queue", target: queue), task: task)
  }
}

extension Stream
{
  public func onError(qos: DispatchQoS = DispatchQoS.current(), task: @escaping (Error) -> Void)
  {
    onError(queue: DispatchQueue.global(qos: qos.qosClass), task: task)
  }

  public func onError(queue: DispatchQueue, task: @escaping (Error) -> Void)
  {
    let local = DispatchQueue(label: "local-notify-queue", attributes: DispatchQueue.Attributes.concurrent, target: queue)

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .error(let error) = result
        {
          local.async { task(error) }
        }
      }
    )
  }
}

extension Stream
{
  public func onCompletion(qos: DispatchQoS = DispatchQoS.current(), task: @escaping (StreamCompleted) -> Void)
  {
    onCompletion(queue: DispatchQueue.global(qos: qos.qosClass), task: task)
  }

  public func onCompletion(queue: DispatchQueue, task: @escaping (StreamCompleted) -> Void)
  {
    let local = DispatchQueue(label: "local-notify-queue", attributes: DispatchQueue.Attributes.concurrent, target: queue)

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        q, result in
        assert(q === queue)
        if case .error(let status as StreamCompleted) = result
        {
          local.async { task(status) }
        }
      }
    )
  }
}

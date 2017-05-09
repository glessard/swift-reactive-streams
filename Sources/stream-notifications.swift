//
//  stream-notifications.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

extension EventStream
{
  private func performNotify(_ validated: ValidatedQueue, task: @escaping (Result<Value>) -> Void)
  {
    let queue = validated.queue

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        _, result in
        queue.async { task(result) }
      }
    )
  }

  public func notify(qos: DispatchQoS? = nil, task: @escaping (Result<Value>) -> Void)
  {
    performNotify(ValidatedQueue(label: "notify", qos: qos ?? self.qos), task: task)
  }

  public func notify(_ queue: DispatchQueue, task: @escaping (Result<Value>) -> Void)
  {
    performNotify(ValidatedQueue(label: "notify", target: queue), task: task)
  }
}

extension EventStream
{
  private func performOnValue(_ validated: ValidatedQueue, task: @escaping (Value) -> Void)
  {
    let queue = validated.queue

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        _, result in
        switch result
        {
        case .value(let value):
          queue.async { task(value) }
        default:
          break
        }
      }
    )
  }

  public func onValue(qos: DispatchQoS? = nil, task: @escaping (Value) -> Void)
  {
    performOnValue(ValidatedQueue(label: "onvalue", qos: qos ?? self.qos), task: task)
  }

  public func onValue(_ queue: DispatchQueue, task: @escaping (Value) -> Void)
  {
    performOnValue(ValidatedQueue(label: "onvalue", target: queue), task: task)
  }
}

extension EventStream
{
  public func onError(qos: DispatchQoS? = nil, task: @escaping (Error) -> Void)
  {
    let qos = qos?.qosClass ?? DispatchQoS.QoSClass.current ?? .utility
    onError(DispatchQueue.global(qos: qos), task: task)
  }

  public func onError(_ queue: DispatchQueue, task: @escaping (Error) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        _, result in
        switch result
        {
        case .value, .error(_ as StreamCompleted):
          break
        case .error(let error):
          queue.async { task(error) }
        }
      }
    )
  }
}

extension EventStream
{
  public func onCompletion(qos: DispatchQoS? = nil, task: @escaping (StreamCompleted) -> Void)
  {
    let qos = qos?.qosClass ?? DispatchQoS.QoSClass.current ?? .utility
    onCompletion(DispatchQueue.global(qos: qos), task: task)
  }

  public func onCompletion(_ queue: DispatchQueue, task: @escaping (StreamCompleted) -> Void)
  {
    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { _ in },
      notificationHandler: {
        _, result in
        switch result
        {
        case .error(let completion as StreamCompleted):
          queue.async { task(completion) }
        default:
          break
        }
      }
    )
  }
}

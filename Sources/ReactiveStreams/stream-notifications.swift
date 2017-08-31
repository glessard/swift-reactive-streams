//
//  stream-notifications.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension EventStream
{
  private func performNotify(_ validated: ValidatedQueue, task: @escaping (Event<Value>) -> Void)
  {
    let queue = validated.queue

    self.subscribe(
      subscriber: queue,
      subscriptionHandler: { $0.requestAll() },
      notificationHandler: {
        _, event in
        queue.async { task(event) }
      }
    )
  }

  public func notify(qos: DispatchQoS? = nil, task: @escaping (Event<Value>) -> Void)
  {
    performNotify(ValidatedQueue(label: "notify", qos: qos ?? self.qos), task: task)
  }

  public func notify(_ queue: DispatchQueue, task: @escaping (Event<Value>) -> Void)
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
        _, event in
        if case .value(let value) = event
        {
          queue.async { task(value) }
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
        _, event in
        if case .error(let error) = event, !(error is StreamCompleted)
        {
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
        _, event in
        if case .error(let final as StreamCompleted) = event
        {
          queue.async { task(final) }
        }
      }
    )
  }
}

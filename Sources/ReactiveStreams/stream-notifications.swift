//
//  stream-notifications.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

private class NotificationSubscriber<Value>: Subscriber
{
  private let queue: DispatchQueue
  private var subscription: Subscription? = nil

  var valueHandler: ((Value) -> Void)? = nil
  var errorHandler: ((Error) -> Void)? = nil
  var completionHandler: (() -> Void)? = nil

  init(_ queue: DispatchQueue)
  {
    self.queue = queue
  }

  func onSubscription(_ subscription: Subscription)
  { // never accept a subscription if we already have one
    self.subscription = self.subscription ?? subscription
    // only request events if the event handler for value exists
    if valueHandler != nil { subscription.requestAll() }
  }

  func onValue(_ value: Value)
  {
    if let handler = self.valueHandler { queue.async { handler(value) } }
  }

  func onError(_ error: Error)
  {
    queue.async {
      if let handler = self.errorHandler { handler(error) }
      self.cleanup()
    }
  }

  func onCompletion()
  {
    queue.async {
      if let handler = self.completionHandler { handler() }
      self.cleanup()
    }
  }

  private func cleanup()
  {
    valueHandler = nil
    errorHandler = nil
    completionHandler = nil
  }
}

extension EventStream
{
  private func performOnEvent(_ validated: ValidatedQueue, task: @escaping (Event<Value>) -> Void)
  {
    let notifier = NotificationSubscriber<Value>(validated.queue)
    notifier.valueHandler = { task(Event(value: $0)) }
    // making Subscriber.notify overrideable might be better, but not problem-free
    notifier.errorHandler = { task(Event(error: $0)) }
    notifier.completionHandler = { withExtendedLifetime(notifier) { task(Event.streamCompleted) } }

    self.subscribe(notifier)
  }

  public func onEvent(qos: DispatchQoS? = nil, task: @escaping (Event<Value>) -> Void)
  {
    performOnEvent(ValidatedQueue(label: "notify", qos: qos ?? self.qos), task: task)
  }

  public func onEvent(queue: DispatchQueue, task: @escaping (Event<Value>) -> Void)
  {
    performOnEvent(ValidatedQueue(label: "notify", target: queue), task: task)
  }
}

extension EventStream
{
  private func performOnValue(_ validated: ValidatedQueue, task: @escaping (Value) -> Void)
  {
    let notifier = NotificationSubscriber<Value>(validated.queue)
    notifier.valueHandler = { value in withExtendedLifetime(notifier) { task(value) } }
    self.subscribe(notifier)
  }

  public func onValue(qos: DispatchQoS? = nil, task: @escaping (Value) -> Void)
  {
    performOnValue(ValidatedQueue(label: "onvalue", qos: qos ?? self.qos), task: task)
  }

  public func onValue(queue: DispatchQueue, task: @escaping (Value) -> Void)
  {
    performOnValue(ValidatedQueue(label: "onvalue", target: queue), task: task)
  }
}

extension EventStream
{
  public func onError(qos: DispatchQoS? = nil, task: @escaping (Error) -> Void)
  {
    let queue = DispatchQueue(label: "concurrent", qos: qos ?? self.qos, attributes: .concurrent)
    onError(queue: queue, task: task)
  }

  public func onError(queue: DispatchQueue, task: @escaping (Error) -> Void)
  {
    let notifier = NotificationSubscriber<Value>(queue)
    notifier.errorHandler = { error in withExtendedLifetime(notifier) { task(error) } }
    self.subscribe(notifier)
  }
}

extension EventStream
{
  public func onCompletion(qos: DispatchQoS? = nil, task: @escaping () -> Void)
  {
    let queue = DispatchQueue(label: "concurrent", qos: qos ?? self.qos, attributes: .concurrent)
    onCompletion(queue: queue, task: task)
  }

  public func onCompletion(queue: DispatchQueue, task: @escaping () -> Void)
  {
    let notifier = NotificationSubscriber<Value>(queue)
    notifier.completionHandler = { withExtendedLifetime(notifier) { task() } }
    self.subscribe(notifier)
  }
}

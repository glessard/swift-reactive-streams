//
//  stream-notifier.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 5/29/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class StreamNotifier<Value>
{
  private let sub = LockedSubscription()
  private let queue: DispatchQueue

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onEvent: @escaping (Event<Value>) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0); $0.requestAll() },
      notificationHandler: {
        notifier, event in
        notifier.queue.async {
          onEvent(event)
          if event.isValue == false { _ = notifier.sub.take() }
        }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onEvent: @escaping(Subscription, Event<Value>) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0) },
      notificationHandler: {
        notifier, subscription, event in
        notifier.queue.async {
          onEvent(subscription, event)
          if event.isValue == false { _ = notifier.sub.take() }
        }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onValue: @escaping (Value) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0); $0.requestAll() },
      notificationHandler: {
        notifier, event in
        if let value = event.value
        { notifier.queue.async { onValue(value) } }
        else
        { _ = notifier.sub.take() }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onValue: @escaping (Subscription, Value) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0) },
      notificationHandler: {
        notifier, subscription, event in
        if let value = event.value
        { notifier.queue.async { onValue(subscription, value) } }
        else
        { _ = notifier.sub.take() }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onError: @escaping (Error) -> Void)
  {
    self.queue = queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0) },
      notificationHandler: {
        notifier, event in
        assert(event.value == nil)
        if let error = event.error { notifier.queue.async { onError(error) } }
        _ = notifier.sub.take()
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onCompletion: @escaping () -> Void)
  {
    self.queue = queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.assign($0) },
      notificationHandler: {
        notifier, event in
        assert(event.value == nil)
        if event.state == nil { notifier.queue.async { onCompletion() } }
        _ = notifier.sub.take()
      }
    )
  }

  public func request(_ count: Int)
  {
    let subscription = sub.load()
    subscription?.request(count)
  }

  public func close()
  {
    let subscription = sub.load()
    subscription?.cancel()
  }

  deinit {
    let subscription = sub.take()
    subscription?.cancel()
  }
}

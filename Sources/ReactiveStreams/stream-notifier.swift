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
  private var subscription: Subscription?

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onEvent: @escaping (Event<Value>) -> Void)
  {
    let queue = ValidatedQueue(label: #function, target: queue)
    stream.subscribe(
      subscriptionHandler: { self.subscription = $0; $0.requestAll() },
      notificationHandler: {
        [weak self, queue = queue.queue] event in
        queue.async {
          onEvent(event)
          if event.isValue == false { self?.subscription = nil }
        }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onValue: @escaping (Value) -> Void)
  {
    let queue = ValidatedQueue(label: #function, target: queue)
    stream.subscribe(
      subscriptionHandler: { self.subscription = $0; $0.requestAll() },
      notificationHandler: {
        [weak self, queue = queue.queue] event in
        if let value = event.value
        { queue.async { onValue(value) } }
        else
        { self?.subscription = nil }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onError: @escaping (Error) -> Void)
  {
    stream.subscribe(
      subscriptionHandler: { self.subscription = $0 },
      notificationHandler: {
        [weak self] event in
        assert(event.value == nil)
        if let error = event.error { queue.async { onError(error) } }
        self?.subscription = nil
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onCompletion: @escaping () -> Void)
  {
    stream.subscribe(
      subscriptionHandler: { self.subscription = $0 },
      notificationHandler: {
        [weak self] event in
        assert(event.value == nil)
        if event.state == nil { queue.async { onCompletion() } }
        self?.subscription = nil
      }
    )
  }

  public func close()
  {
    subscription?.cancel()
    subscription = nil
  }

  deinit {
    subscription?.cancel()
  }
}

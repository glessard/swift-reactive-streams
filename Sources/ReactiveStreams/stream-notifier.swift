//
//  stream-notifier.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 5/29/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

public class StreamNotifier<Value>
{
  private var sub = UnsafeMutablePointer<OpaqueUnmanagedHelper>.allocate(capacity: 1)
  private let queue: DispatchQueue

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onEvent: @escaping (Event<Value>) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.initialize($0); $0.requestAll() },
      notificationHandler: {
        notifier, event in
        notifier.queue.async {
          onEvent(event)
          if event.isValue == false { notifier.close() }
        }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onValue: @escaping (Value) -> Void)
  {
    self.queue = ValidatedQueue(label: #function, target: queue).queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.initialize($0); $0.requestAll() },
      notificationHandler: {
        notifier, event in
        if let value = event.value
        { notifier.queue.async { onValue(value) } }
        else
        { notifier.close() }
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onError: @escaping (Error) -> Void)
  {
    self.queue = queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.initialize($0) },
      notificationHandler: {
        notifier, event in
        assert(event.value == nil)
        if let error = event.error { notifier.queue.async { onError(error) } }
        notifier.close()
      }
    )
  }

  public init(_ stream: EventStream<Value>, queue: DispatchQueue = .main, onCompletion: @escaping () -> Void)
  {
    self.queue = queue
    stream.subscribe(
      subscriber: self,
      subscriptionHandler: { self.sub.initialize($0) },
      notificationHandler: {
        notifier, event in
        assert(event.value == nil)
        if event.state == nil { notifier.queue.async { onCompletion() } }
        notifier.close()
      }
    )
  }

  public func close()
  {
    let subscription = sub.take()
    subscription?.cancel()
  }

  deinit {
    let subscription = sub.take()
    subscription?.cancel()
    sub.deallocate()
  }
}

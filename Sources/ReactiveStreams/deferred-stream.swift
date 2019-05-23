//
//  deferred-stream.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

public class DeferredStream<Value>: EventStream<Value>
{
  private var deferred: Deferred<Value>?

  convenience public init(qos: DispatchQoS? = nil, from deferred: Deferred<Value>)
  {
    let v = ValidatedQueue(label: "stream-from-deferred", qos: qos ?? deferred.qos)
    self.init(validated: v, from: deferred)
  }

  convenience public init(queue: DispatchQueue, from deferred: Deferred<Value>)
  {
    let v = ValidatedQueue(label: "stream-from-deferred", target: queue)
    self.init(validated: v, from: deferred)
  }

  private init(validated: ValidatedQueue, from deferred: Deferred<Value>)
  {
    self.deferred = deferred
    super.init(validated: validated)

    deferred.notify(queue: validated.queue) {
      [weak self] result in
      self?.dispatch(result)
    }
  }

  private func dispatch(_ result: Result<Value, Error>)
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    guard requested > 0 else { return }

    let event = Event(result)
    dispatch(event)
    deferred = nil
    if event.isValue
    {
      dispatch(Event.streamCompleted)
    }
  }

  open override func updateRequest(_ requested: Int64)
  {
    precondition(requested > 0)
    super.updateRequest(1)
  }

  open override func processAdditionalRequest(_ additional: Int64)
  {
    if let result = deferred?.peek()
    {
      queue.async {
        [weak self] in
        self?.dispatch(result)
      }
    }
  }
}

extension Deferred
{
  public var eventStream: EventStream<Value> { return DeferredStream(from: self) }
}

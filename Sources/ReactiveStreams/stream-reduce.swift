//
//  stream-reduce.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

class ReducingStream<InputValue, OutputValue>: SubStream<OutputValue>
{
  private var current: OutputValue
  private let combiner: (inout OutputValue, InputValue) throws -> Void

  init(_ validated: ValidatedQueue, initial: OutputValue, combiner: @escaping (inout OutputValue, InputValue) throws -> Void)
  {
    self.current = initial
    self.combiner = combiner
    super.init(validated: validated)
  }

  init(_ validated: ValidatedQueue, initial: OutputValue, combiner: @escaping (OutputValue, InputValue) throws -> OutputValue)
  {
    self.current = initial
    self.combiner = { $0 = try combiner ($0, $1) }
    super.init(validated: validated)
  }

  override func setSubscription(_ subscription: Subscription)
  {
    super.setSubscription(subscription)
    subscription.requestAll()
  }

  func processEvent(_ event: Event<InputValue>)
  {
    queue.async {
      do {
        try self.combiner(&self.current, event.get())
      }
      catch {
        self.dispatch(Event(value: self.current))
        self.dispatch(Event(error: error))
      }
    }
  }

  @discardableResult
  override func updateRequest(_ requested: Int64) -> Int64
  { // only pass on requested updates up to and including our remaining number of events
    precondition(requested > 0)
    return super.updateRequest(1)
  }
}

extension EventStream
{
  private func reduce<U>(_ reducer: ReducingStream<Value, U>) -> EventStream<U>
  {
    self.subscribe(substream: reducer) { $0.processEvent($1) }
    return reducer
  }

  public func reduce<U>(qos: DispatchQoS? = nil, _ initial: U, _ combiner: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    let queue = ValidatedQueue(label: "reducing-queue", qos: qos ?? self.qos)
    return reduce(ReducingStream(queue, initial: initial, combiner: combiner))
  }

  public func reduce<U>(queue: DispatchQueue, _ initial: U, _ combiner: @escaping (U, Value) throws -> U) -> EventStream<U>
  {
    let queue = ValidatedQueue(label: "reducing-queue", target: queue)
    return reduce(ReducingStream(queue, initial: initial, combiner: combiner))
  }

  public func reduce<U>(qos: DispatchQoS? = nil, into initial: U, _ combiner: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    let queue = ValidatedQueue(label: "reducing-queue", qos: qos ?? self.qos)
    return reduce(ReducingStream(queue, initial: initial, combiner: combiner))
  }

  public func reduce<U>(queue: DispatchQueue, into initial: U, _ combiner: @escaping (inout U, Value) throws -> Void) -> EventStream<U>
  {
    let queue = ValidatedQueue(label: "reducing-queue", target: queue)
    return reduce(ReducingStream(queue, initial: initial, combiner: combiner))
  }
}

extension EventStream
{
  public func countEvents(qos: DispatchQoS? = nil) -> EventStream<Int>
  {
    return self.reduce(qos: qos, into: 0) { (count: inout Int, _) in count += 1 }
  }

  public func countEvents(queue: DispatchQueue) -> EventStream<Int>
  {
    return self.reduce(queue: queue, into: 0) { (count: inout Int, _) in count += 1 }
  }
}

extension EventStream
{

  public func coalesce(qos: DispatchQoS? = nil) -> EventStream<[Value]>
  {
    return self.reduce(qos: qos, into: []) { (c: inout [Value], e: Value) in c.append(e) }
  }

  public func coalesce(queue: DispatchQueue) -> EventStream<[Value]>
  {
    return self.reduce(queue: queue, into: []) { (c: inout [Value], e: Value) in c.append(e) }
  }
}

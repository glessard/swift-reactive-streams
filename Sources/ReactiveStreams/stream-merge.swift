//
//  stream-merge.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class MergeStream<Value>: SubStream<Value, Value>
{
  fileprivate var sources = Set<Subscription>()
  fileprivate var closed = false
  fileprivate let closeAfterLastSourceCloses: Bool

  override init(validated: ValidatedQueue)
  {
    closeAfterLastSourceCloses = true
    super.init(validated: validated)
  }

  fileprivate init(validated: ValidatedQueue, flatMap: Bool = false)
  {
    closeAfterLastSourceCloses = !flatMap
    super.init(validated: validated)
  }

  public func merge(_ source: EventStream<Value>)
  {
    queue.async { self.performMerge(source) }
  }

  /// precondition: must run on a barrier block or a serial queue

  func performMerge(_ source: EventStream<Value>)
  {
    if closed { return }

    var subscription: Subscription! = nil

    source.subscribe(
      subscriber: self,
      subscriptionHandler: {
        sub in
        subscription = sub
        self.sources.insert(sub)
        sub.request(self.requested)
      },
      notificationHandler: {
        merged, event in
        merged.queue.async {
          if event.isValue == false
          { // event terminates merged stream; remove it from sources
            merged.sources.remove(subscription)
            if event.final != nil
            { // merged stream completed normally
              if (merged.closeAfterLastSourceCloses || merged.closed), merged.sources.isEmpty
              { // no other event is forthcoming from any stream
                merged.dispatch(Event.streamCompleted)
              }
              return
            }
          }
          merged.dispatch(event)
        }
      }
    )
  }

  /// precondition: must run on a barrier block or a serial queue

  public override func finalizeStream()
  {
    closed = true
    for source in sources
    { // sources may not be empty if we have an actual error as a terminating event
      source.cancel()
    }
    sources.removeAll()
    super.finalizeStream()
  }

  public override func close()
  {
    guard !completed else { return }
    queue.async {
      self.closed = true
      self.dispatch(Event.streamCompleted)
    }
  }

  @discardableResult
  public override func updateRequest(_ requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    // copy sources so that a modification in the main queue doesn't interfere.
    // (optimistic? should this use dispatch_barrier_async instead?)
    let s = sources
    for subscription in s
    {
      subscription.request(additional)
    }
    return additional
  }
}

internal class FlatMapStream<Value>: MergeStream<Value>
{
  convenience init(qos: DispatchQoS = DispatchQoS.current)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", qos: qos))
  }

  convenience init(_ queue: DispatchQueue)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", target: queue))
  }

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated, flatMap: true)
  }

  public override func close()
  {
    queue.async {
      self.closed = true
      if self.sources.isEmpty
      {
        self.dispatch(Event.streamCompleted)
      }
    }
  }
}

extension EventStream
{
  private func flatMap<U>(_ stream: FlatMapStream<U>, transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    self.subscribe(
      subscriber: stream,
      subscriptionHandler: stream.setSubscription,
      notificationHandler: {
        merged, event in
        merged.queue.async {
          do {
            merged.performMerge(transform(try event.get()))
          }
          catch StreamCompleted.normally {
            merged.close()
          }
          catch {
            merged.dispatch(Event(error: error))
          }
        }
    }
    )
    return stream
  }

  public func flatMap<U>(qos: DispatchQoS? = nil, transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    return flatMap(FlatMapStream(qos: qos ?? self.qos), transform: transform)
  }

  public func flatMap<U>(_ queue: DispatchQueue, transform: @escaping (Value) -> EventStream<U>) -> EventStream<U>
  {
    return flatMap(FlatMapStream(queue), transform: transform)
  }
}

extension EventStream
{
  public func merge(with other: EventStream<Value>) -> EventStream<Value>
  {
    let merged = MergeStream<Value>(qos: self.queue.qos)

    merged.queue.async {
      merged.performMerge(self)
      merged.performMerge(other)
    }

    return merged
  }
}

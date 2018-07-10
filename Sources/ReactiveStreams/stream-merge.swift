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

  fileprivate let closeWhenLastSourceCloses: Bool
  fileprivate let delayErrorReporting: Bool
  private var delayedError: Error?

  fileprivate convenience init(qos: DispatchQoS = DispatchQoS.current, delayingErrors delay: Bool)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", qos: qos), delayingErrors: delay)
  }

  fileprivate convenience init(_ queue: DispatchQueue, delayingErrors delay: Bool)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", target: queue), delayingErrors: delay)
  }

  fileprivate init(validated: ValidatedQueue, flatMap: Bool = false, delayingErrors delay: Bool)
  {
    closeWhenLastSourceCloses = !flatMap
    delayErrorReporting = delay
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
              if (merged.closeWhenLastSourceCloses || merged.closed), merged.sources.isEmpty
              { // no other event is forthcoming from any stream
                let errorEvent = merged.delayedError.map(Event<Value>.init(error:))
                merged.dispatch(errorEvent ?? Event.streamCompleted)
              }
              return
            }
            else if merged.delayErrorReporting
            {
              let error = merged.delayedError ?? event.error!
              merged.delayedError = error
              if merged.sources.isEmpty
              {
                merged.dispatch(Event(error: error))
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

  init(validated: ValidatedQueue)
  {
    super.init(validated: validated, flatMap: true, delayingErrors: false)
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
  static public func merge(_ stream1: EventStream<Value>, _ stream2: EventStream<Value>, delayingErrors delay: Bool = false) -> EventStream<Value>
  {
    return merge(streams: [stream1, stream2], delayingErrors: delay)
  }

  static private func merge<S: Sequence>(streams: S, into merged: MergeStream<Value>)
    where S.Iterator.Element: EventStream<Value>
  {
    merged.queue.async {
      streams.forEach {
        merged.performMerge($0)
      }
    }
  }

  static public func merge<S: Sequence>(qos: DispatchQoS = DispatchQoS.current, streams: S, delayingErrors delay: Bool = false) -> EventStream<Value>
    where S.Iterator.Element: EventStream<Value>
  {
    let merged = MergeStream<Value>(qos: qos, delayingErrors: delay)
    merge(streams: streams, into: merged)
    return merged
  }

  static public func merge<S: Sequence>(_ queue: DispatchQueue, streams: S, delayingErrors delay: Bool = false) -> EventStream<Value>
    where S.Iterator.Element: EventStream<Value>
  {
    let merged = MergeStream<Value>(queue, delayingErrors: delay)
    merge(streams: streams, into: merged)
    return merged
  }

  public func merge(with other: EventStream<Value>) -> EventStream<Value>
  {
    return EventStream.merge(qos: qos, streams: [self, other], delayingErrors: false)
  }

  public func merge<S: Sequence>(with others: S) -> EventStream<Value>
    where S.Iterator.Element: EventStream<Value>
  {
    let merged = MergeStream<Value>(qos: qos, delayingErrors: false)
    merged.queue.async {
      merged.performMerge(self)
      others.forEach { merged.performMerge($0) }
    }
    return merged
  }
}

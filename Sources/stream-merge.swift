//
//  stream-merge.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public class MergeStream<Value>: SerialSubStream<Value, Value>
{
  private var sources = Set<Subscription>()
  private var closed = false

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  public func merge(source: Stream<Value>)
  {
    if self.closed { return }

    dispatch_barrier_async(self.queue) {
      self.performMerge(source)
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  func performMerge(source: Stream<Value>)
  {
    guard !self.closed else { return }

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
        merged, result in
        dispatch_async(merged.queue) {
          switch result
          {
          case .value:
            merged.dispatchValue(result)
          case .error(_ as StreamCompleted):
            merged.sources.remove(subscription)
            if merged.closed && merged.sources.isEmpty
            {
              merged.dispatchError(result)
            }
          case .error:
            merged.sources.remove(subscription)
            merged.dispatchError(result)
          }
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
    dispatch_barrier_async(queue) {
      self.closed = true
      if self.sources.isEmpty
      {
        self.dispatchError(Result.error(StreamCompleted.normally))
      }
    }
  }

  public override func updateRequest(requested: Int64) -> Int64
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

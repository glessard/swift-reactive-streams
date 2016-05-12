//
//  stream-merge.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class MergeStream<Value>: SerialSubStream<Value,Value>
{
  private var sources = Set<Subscription>()
  private var closed = false

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  public func merge(source: Stream<Value>)
  {
    if state == StreamState.ended { return }

    dispatch_barrier_async(self.queue) {
      guard !self.closed else { return }

      source.subscribe({
        subscription in
        self.sources.insert(subscription)
        subscription.request(self.requested)
        },
        handler: {
          subscription, result in
          self.process {
            switch result
            {
            case .value:
              return result
            case .error(_ as StreamCompleted):
              subscription.cancel()
              self.sources.remove(subscription)
              if self.closed && self.sources.isEmpty
              { return result }
              else
              { return nil }
            case .error:
              subscription.cancel()
              self.sources.remove(subscription)
              return result
            }
          }
        }
      )
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  public override func finalizeStream()
  {
    closed = true
    for subscription in sources
    {
      subscription.cancel()
    }
    sources.removeAll()
    super.finalizeStream()
  }

  public override func close()
  {
    process {
      self.closed = true
      if self.sources.isEmpty
      {
        return Result.error(StreamCompleted.terminated)
      }
      return nil
    }
  }

  public override func setRequested(requested: Int64) -> Int64
  {
    let additional = super.setRequested(requested)
    // copy sources so that a modification in the main queue doesn't interfere.
    // (optimistic?)
    let s = sources
    for subscription in s
    {
      subscription.request(additional)
    }
    return additional
  }
}

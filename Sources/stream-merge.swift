//
//  stream-merge.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class MergeStream<Value>: SerialStream<Value>
{
  private var sources = Set<Stream<Value>>()
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

      self.sources.insert(source)
      source.addObserver(self) {
        result in
        self.process {
          switch result
          {
          case .value:
            return result
          case .error(_ as StreamClosed):
            self.sources.remove(source)
            source.removeObserver(self)
            if self.closed && self.sources.isEmpty
            { return result }
            else
            { return nil }
          case .error:
            self.sources.remove(source)
            source.removeObserver(self)
            return result
          }
        }
      }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  public override func finalizeStream()
  {
    closed = true
    for source in sources
    {
      source.removeObserver(self)
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
        return Result.error(StreamClosed.ended)
      }
      return nil
    }
  }
}

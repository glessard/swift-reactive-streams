//
//  subscription.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

final public class Subscription
{
  private weak var source: Source?

  public private(set) var requested: Int64
  public private(set) var cancelled: Int32 = 0

  public init(source: Source)
  {
    self.source = source
    self.requested = 0
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    if requested == Int64.max
    {
      return true
    }

    if requested > 0
    {
      let decremented = OSAtomicAdd64Barrier(-1, &requested)
      if decremented >= 0
      {
        return true
      }
      // prudently set it back to 0
      while true
      {
        let fixit = requested
        if fixit >= 0
        { // another thread got it back above zero
          return fixit != 0
        }
        if OSAtomicCompareAndSwap64(fixit, 0, &requested)
        {
          return false
        }
      }
    }

    return false
  }

  // called by the subscriber

  public func requestAll()
  {
    request(Int64.max)
  }

  // called by the subscriber

  public func request(count: Int64)
  {
    if cancelled == 0
    {
      let curreq = requested
      guard curreq < Int64.max else { return }
      guard count > 0 else { return }

      if count < Int64.max && (count &+ curreq > 0)
      {
        let newDemand = OSAtomicAdd64(count, &requested)
        if let source = source { source.setRequested(newDemand) }
        return
      }

      // set requested to Int64.max
      while true
      { // an atomic store would be nice
        let req = requested
        if OSAtomicCompareAndSwap64(req, Int64.max, &requested)
        {
          if let source = source { source.setRequested(Int64.max) }
          break
        }
      }
    }
  }

  public func cancel()
  {
    if OSAtomicCompareAndSwap32Barrier(0, 1, &cancelled)
    {
      if let source = source
      {
        source.cancel(subscription: self)
        self.source = nil
      }
      requested = 0 // atomic store might be nicer
    }
  }
}

extension Subscription: Equatable {}

public func == (lhs: Subscription, rhs: Subscription) -> Bool
{
  return lhs === rhs
}

extension Subscription: Hashable
{
  public var hashValue: Int { return unsafeAddressOf(self).hashValue }
}

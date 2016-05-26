//
//  subscription.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

final public class Subscription
{
  private var source: Source?

  public private(set) var requested: Int64

  public var cancelled: Bool { return requested == Int64.min }

  init(source: Source)
  {
    self.source = source
    self.requested = 0
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var p = requested
    if p == Int64.max { return true }

    while p > 0
    {
      if OSAtomicCompareAndSwap64(p, p-1, &requested)
      {
        return true
      }
      p = requested
    }

    return false
  }

  // called by our subscriber

  public func requestAll()
  {
    request(Int64.max)
  }

  // called by our subscriber

  public func request(count: Int64)
  {
    if count < 1 { return }

    var p = requested
    precondition(p == Int64.min || p >= 0)
    while p != Int64.min && p < Int64.max
    {
      let tentatively = p &+ count // could technically overflow; avoid trapping
      let updatedRequest = tentatively > 0 ? tentatively : Int64.max
      if OSAtomicCompareAndSwap64(p, updatedRequest, &requested)
      {
        if let source = source { source.updateRequest(updatedRequest) }
        return
      }
      p = requested
    }
  }

  // called by our subscriber

  public func cancel()
  {
    var p = requested
    guard p != Int64.min else { return }

    // an atomic store would do better here.
    while !OSAtomicCompareAndSwap64Barrier(p, Int64.min, &requested)
    {
      p = requested
    }

    if let source = source
    {
      source.cancel(subscription: self)
      self.source = nil
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

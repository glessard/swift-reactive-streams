//
//  subscription.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import func Darwin.OSAtomicCompareAndSwap64

final public class Subscription
{
  private var source: Publisher?

  public private(set) var requested: Int64

  public var cancelled: Bool { return requested == Int64.min }

  init(source: Publisher)
  {
    self.source = source
    self.requested = 0
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var p: Int64
    repeat {
      p = requested
      if p == Int64.max { break }
      if p <= 0 { return false }
    } while !OSAtomicCompareAndSwap64(p, p-1, &requested)
    return true
  }

  // called by our subscriber

  public func requestAll()
  {
    request(Int64.max)
  }

  public func request(_ count: Int)
  {
    request(Int64(count))
  }

  // called by our subscriber

  public func request(_ count: Int64)
  {
    if count < 1 { return }

    var prev, updated: Int64
    repeat {
      prev = requested
      if prev == Int64.min || prev == Int64.max { return }
      assert(prev >= 0)

      let tentatively = prev &+ count // could overflow; avoid trapping
      updated = tentatively > 0 ? tentatively : Int64.max
    } while !OSAtomicCompareAndSwap64(prev, updated, &requested)
    source?.updateRequest(updated)
  }

  // called by our subscriber

  public func cancel()
  {
    var prev: Int64
    repeat {
      prev = requested
      if prev == Int64.min { return }
    } while !OSAtomicCompareAndSwap64(prev, Int64.min, &requested)

    source?.cancel(subscription: self)
    source = nil
  }
}

extension Subscription: Equatable {}

public func == (lhs: Subscription, rhs: Subscription) -> Bool
{
  return lhs === rhs
}

extension Subscription: Hashable
{
  public var hashValue: Int { return ObjectIdentifier(self).hashValue }
}

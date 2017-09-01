//
//  subscription.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import CAtomics

final public class Subscription
{
  private var source: EventSource?

  private var requested = CAtomicsInt64()

  public var cancelled: Bool { return CAtomicsInt64Load(&requested, .relaxed) == Int64.min }

  init(source: EventSource)
  {
    self.source = source
    CAtomicsInt64Init(0, &requested)
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var p: Int64 = 1
    while !CAtomicsInt64CAS(&p, p-1, &requested, .weak, .relaxed, .relaxed)
    {
      if p == Int64.max { break }
      if p <= 0 { return false }
    }
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

    var updated: Int64
    var current = CAtomicsInt64Load(&requested, .relaxed)
    repeat {
      if current == Int64.min || current == Int64.max { return }
      let tentatively = current &+ count // could overflow; avoid trapping
      updated = tentatively > 0 ? tentatively : Int64.max
    } while !CAtomicsInt64CAS(&current, updated, &requested, .weak, .relaxed, .relaxed)

    source?.updateRequest(updated)
  }

  // called by our subscriber

  public func cancel()
  {
    let prev = CAtomicsInt64Swap(Int64.min, &requested, .relaxed)
    guard prev != Int64.min else { return }

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

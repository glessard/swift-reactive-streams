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

  private var requested = AtomicInt64()

  public var cancelled: Bool { return requested.load(.relaxed) == .min }

  init(source: EventSource)
  {
    self.source = source
    requested.initialize(0)
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var remaining = requested.load(.relaxed)
    repeat {
      if remaining == .max { break }
      if remaining <= 0 { return false }
    } while !requested.loadCAS(&remaining, remaining-1, .weak, .relaxed, .relaxed)
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
    var current = requested.load(.relaxed)
    repeat {
      if current == .min || current == .max { return }
      updated = current &+ count // could overflow; avoid trapping
      if updated < 0 { updated = .max } // check and correct for overflow
    } while !requested.loadCAS(&current, updated, .weak, .relaxed, .relaxed)

    source?.updateRequest(updated)
  }

  // called by our subscriber

  public func cancel()
  {
    let prev = requested.swap(.min, .relaxed)
    if prev == .min { return }

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

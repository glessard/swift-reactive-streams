//
//  subscription.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import CAtomics

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import func Darwin.sched_yield
#else
import func Glibc.sched_yield
#endif

final public class Subscription
{
  private static let serial: UnsafeMutablePointer<AtomicUInt64> = {
    let p = UnsafeMutablePointer<AtomicUInt64>.allocate(capacity: 1)
    CAtomicsInitialize(p, 0)
    return p
  }()

  private let source: EventSource
  private let requested = UnsafeMutablePointer<AtomicInt64>.allocate(capacity: 1)

  public let id: UInt64

  public var cancelled: Bool { return CAtomicsLoad(requested, .relaxed) == .min }

  init<P: Publisher>(publisher: P)
  {
    self.source = publisher as EventSource
    self.id = CAtomicsAdd(Subscription.serial, 1, .relaxed)
    CAtomicsInitialize(requested, 0)
  }
  
  deinit {
    requested.deallocate()
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var remaining = CAtomicsLoad(requested, .relaxed)
    repeat {
      if remaining == .max { break }
      if remaining <= 0 { return false }
    } while !CAtomicsCompareAndExchange(requested, &remaining, remaining-1, .weak, .relaxed, .relaxed)
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
    var current = CAtomicsLoad(requested, .relaxed)
    repeat {
      if current == .min || current == .max { return }
      updated = current &+ count // could overflow; avoid trapping
      if updated < 0 { updated = .max } // check and correct for overflow
    } while !CAtomicsCompareAndExchange(requested, &current, updated, .weak, .relaxed, .relaxed)

    source.updateRequest(updated)
  }

  // If a subscriber must reduce the number of events it needs to receive,
  // reduce it to zero first, then raise again. This does carry the risk
  // of dropped events.

  public func requestNone()
  {
    var current = CAtomicsLoad(requested, .relaxed)
    repeat {
      if current < 1 { return }
    } while !CAtomicsCompareAndExchange(requested, &current, 0, .weak, .relaxed, .relaxed)
  }

  // called by our subscriber

  public func cancel()
  {
    var prev = CAtomicsLoad(requested, .relaxed)
    repeat {
      if prev == .min { return }
    } while !CAtomicsCompareAndExchange(requested, &prev, .min, .weak, .relaxed, .relaxed)

    source.cancel(subscription: self)
  }

  internal func cancel<P: Publisher>(_ publisher: P)
  {
    if (publisher as EventSource) === source
    {
      CAtomicsStore(requested, .min, .relaxed)
    }
  }
}

extension Subscription: Equatable
{
  public static func == (lhs: Subscription, rhs: Subscription) -> Bool
  {
    return (lhs === rhs)
  }
}

extension Subscription: Hashable
{
  public func hash(into hasher: inout Hasher)
  {
    id.hash(into: &hasher)
  }
}

#if compiler(>=5.1)
extension Subscription: Identifiable {}
#endif

class LockedSubscription
{
  private var locked = UnsafeMutablePointer<AtomicBool>.allocate(capacity: 1)
  private var subscription: Subscription? = nil

  init()
  {
    CAtomicsInitialize(locked, false)
  }

  deinit {
    locked.deallocate()
  }

  private func lock()
  {
    var c = 0
    while !CAtomicsCompareAndExchange(locked, false, true, .weak, .acquire)
    {
      if c > 64
      { _ = sched_yield() }
      else
      { c += 1 }
    }
    precondition(CAtomicsLoad(locked, .relaxed) == true)
  }

  private func unlock()
  {
    CAtomicsStore(locked, false, .release)
  }

  func assign(_ subscription: Subscription)
  {
    lock()
    if self.subscription == nil
    {
      self.subscription = subscription
    }
    unlock()
  }

  func load() -> Subscription?
  {
    lock()
    let s = subscription
    unlock()
    return s
  }

  func take() -> Subscription?
  {
    lock()
    var s: Subscription? = nil
    swap(&s, &subscription)
    unlock()
    return s
  }
}

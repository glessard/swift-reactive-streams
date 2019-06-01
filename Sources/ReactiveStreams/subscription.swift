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
  private let source: EventSource

  private var requested = UnsafeMutablePointer<AtomicInt64>.allocate(capacity: 1)

  public var cancelled: Bool { return CAtomicsLoad(requested, .relaxed) == .min }

  init<P: Publisher>(publisher: P)
  {
    source = publisher as EventSource
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
    return lhs === rhs
  }
}

extension Subscription: Hashable
{
  public func hash(into hasher: inout Hasher)
  {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

struct OneTime<Reference: AnyObject>
{
  private let ref: Unmanaged<Reference>
  private weak var wref: Reference? = nil

  init(_ reference: Reference)
  {
    ref = Unmanaged.passRetained(reference)
    wref = reference
  }

  var reference: Reference? { return wref }

  /// Clear the reference, and return it if it exists.
  /// For any particular instance, all possible uses of this
  /// cannot overlap with one another; use either serially,
  /// in a barrier block or in a deinit.
  ///
  /// Making this a `mutating` function is not a valid way
  /// to enforce the above restriction, as reading a value
  /// is illegal during a mutating access; the restriction
  /// for this method is strictly for simultaneous calls.

  func take() -> Reference?
  {
    guard let reference = wref else { return nil }

    ref.release()
    return reference
  }
}

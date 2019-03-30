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

  private var requested = AtomicInt64()

  public var cancelled: Bool { return CAtomicsLoad(&requested, .relaxed) == .min }

  init<P: Publisher>(publisher: P)
  {
    source = publisher as EventSource
    CAtomicsInitialize(&requested, 0)
  }

  // called by our source

  func shouldNotify() -> Bool
  {
    var remaining = CAtomicsLoad(&requested, .relaxed)
    repeat {
      if remaining == .max { break }
      if remaining <= 0 { return false }
    } while !CAtomicsCompareAndExchange(&requested, &remaining, remaining-1, .weak, .relaxed, .relaxed)
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
    var current = CAtomicsLoad(&requested, .relaxed)
    repeat {
      if current == .min || current == .max { return }
      updated = current &+ count // could overflow; avoid trapping
      if updated < 0 { updated = .max } // check and correct for overflow
    } while !CAtomicsCompareAndExchange(&requested, &current, updated, .weak, .relaxed, .relaxed)

    source.updateRequest(updated)
  }

  // called by our subscriber

  public func cancel()
  {
    var prev = CAtomicsLoad(&requested, .relaxed)
    repeat {
      if prev == .min { return }
    } while !CAtomicsCompareAndExchange(&requested, &prev, .min, .weak, .relaxed, .relaxed)

    source.cancel(subscription: self)
  }

  internal func cancel<P: Publisher>(_ publisher: P)
  {
    if (publisher as EventSource) === source
    {
      CAtomicsStore(&requested, .min, .relaxed)
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
#if swift(>=4.1.50)
  public func hash(into hasher: inout Hasher)
  {
    ObjectIdentifier(self).hash(into: &hasher)
  }
#else
  public var hashValue: Int { return ObjectIdentifier(self).hashValue }
#endif
}

extension OpaqueUnmanagedHelper
{
  mutating func initialize(_ subscription: Subscription?)
  {
    let unmanaged = subscription.map(Unmanaged.passRetained)
    CAtomicsInitialize(&self, unmanaged?.toOpaque())
  }

  mutating func load() -> Subscription?
  {
    guard let pointer = CAtomicsUnmanagedLockAndLoad(&self, .acquire) else { return nil }

    assert(CAtomicsLoad(&self, .acquire) == UnsafeRawPointer(bitPattern: 0x7))
    // atomic container is locked; increment the reference count
    let unmanaged = Unmanaged<Subscription>.fromOpaque(pointer).retain()
    // ensure the reference counting operation has occurred before unlocking,
    // by performing our store operation with StoreMemoryOrder.release
    CAtomicsStore(&self, pointer, .release)
    // atomic container is unlocked
    return unmanaged.takeRetainedValue()
  }

  mutating func take() -> Subscription?
  {
    guard let pointer = CAtomicsExchange(&self, nil, .acquire) else { return nil }
    return Unmanaged.fromOpaque(pointer).takeRetainedValue()
  }
}

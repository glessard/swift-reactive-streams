//
//  stream.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics
import CurrentQoS

public enum StreamState: CustomStringConvertible
{
  case waiting, streaming, ended

  public var description: String {
    switch self
    {
    case .waiting:   return "EventStream waiting to begin processing events"
    case .streaming: return "EventStream active"
    case .ended:     return "EventStream has completed"
    }
  }
}

public enum StreamCompleted: Error
{
  case normally         // after the last value
  case lateSubscription // attempted to subscribe to a completed stream
}

open class EventStream<Value>: Publisher
{
  public typealias EventType = Value

  let queue: DispatchQueue
  private var observers = Dictionary<WeakSubscription, (Subscription, Event<Value>) -> Void>()

  private var pending = UnsafeMutablePointer<AtomicInt64>.allocate(capacity: 1)
  public  var requested: Int64 { return CAtomicsLoad(pending, .relaxed) }
  public  var completed: Bool  { return CAtomicsLoad(pending, .relaxed) == .min }

  public convenience init(qos: DispatchQoS = .current)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", qos: qos))
  }

  public convenience init(queue: DispatchQueue)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", target: queue))
  }

  public init(validated queue: ValidatedQueue)
  {
    CAtomicsInitialize(pending, 0)
    self.queue = queue.queue
  }

  deinit {
    pending.deallocate()
  }

  public var state: StreamState {
    switch requested
    {
    case Int64.min:         return .ended
    case 0:                 return .waiting
    case let n where n > 0: return .streaming
    default: /* n < 0 */    fatalError()
    }
  }

  public var qos: DispatchQoS {
    return queue.qos
  }

  /// precondition: must run on this stream's serial queue

  open func dispatch(_ event: Event<Value>)
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    if event.isValue
    {
      dispatchValue(event)
    }
    else
    {
      dispatchError(event)
    }
  }

  /// precondition: must run on this stream's serial queue

  private func dispatchValue(_ value: Event<Value>)
  {
    assert(value.isValue)

    var prev = CAtomicsLoad(pending, .relaxed)
    repeat {
      if prev == .max { break }
      if prev <= 0 { return }
    } while !CAtomicsCompareAndExchangeWeak(pending, &prev, prev-1, .relaxed, .relaxed)

    var notified = false
    for (ws, notificationHandler) in observers
    {
      if let subscription = ws.subscription
      {
        if subscription.shouldNotify()
        {
          notificationHandler(subscription, value)
          notified = true
        }
      }
      else
      { // subscription no longer exists: remove handler.
        observers.removeValue(forKey: ws)
      }
    }

    if observers.isEmpty
    { lastSubscriptionWasCanceled() }
    else if notified == false
    { didNotNotify() }
  }

  /// precondition: must run on this stream's serial queue

  private func dispatchError(_ error: Event<Value>)
  {
    assert(!error.isValue)

    var prev = CAtomicsLoad(pending, .relaxed)
    repeat {
      if prev == .min { return }
    } while !CAtomicsCompareAndExchangeWeak(pending, &prev, .min, .relaxed, .relaxed)

    for (ws, notificationHandler) in observers
    {
      if let subscription = ws.subscription
      {
        subscription.cancel(self)
        notificationHandler(subscription, error)
      }
    }
    finalizeStream()
  }

  open func close()
  {
    guard !completed else { return }
    queue.async {
      self.dispatch(Event.streamCompleted)
    }
  }

  /// precondition: must run on this stream's serial queue

  open func finalizeStream()
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    observers.removeAll()
  }

  // subscription methods

  final public func subscribe<S: Subscriber>(_ subscriber: S)
    where S.Value == Value
  {
    subscribe(subscriptionHandler: subscriber.onSubscription) {
      [weak subscriber = subscriber] (_, event: Event<Value>) in
      if let subscriber = subscriber { subscriber.onEvent(event) }
    }
  }

  final public func subscribe<S>(substream: S) where S: SubStream<Value>
  {
    subscribe(subscriptionHandler: substream.setSubscription) {
      [weak sub = substream] (_, event: Event<Value>) in
      if let sub = sub { sub.queue.async { sub.dispatch(event) } }
    }
  }

  final public func subscribe<U, S>(substream: S,
                                    notificationHandler: @escaping (S, Event<Value>) -> Void)
    where S: SubStream<U>
  {
    subscribe(subscriptionHandler: substream.setSubscription) {
      [weak subscriber = substream] (_, event: Event<Value>) in
      if let substream = subscriber { notificationHandler(substream, event) }
    }
  }

  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Event<Value>) -> Void)
  {
    subscribe(subscriptionHandler: subscriptionHandler) {
      [weak subscriber = subscriber] (_, event: Event<Value>) in
      if let subscriber = subscriber { notificationHandler(subscriber, event) }
    }
  }

  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Subscription, Event<Value>) -> Void)
  {
    subscribe(subscriptionHandler: subscriptionHandler) {
      [weak subscriber = subscriber] (subscription, event: Event<Value>) in
      if let subscriber = subscriber { notificationHandler(subscriber, subscription, event) }
    }
  }

  final public func subscribe(subscriptionHandler: (Subscription) -> Void,
                              notificationHandler: @escaping (Subscription, Event<Value>) -> Void)
  {
    let subscription = Subscription(publisher: self)

#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .notOnQueue(queue))
    }
#endif

    queue.sync {
      subscriptionHandler(subscription)
      if !completed
      {
        observers[WeakSubscription(subscription)] = notificationHandler
      }
      else
      {
        subscription.cancel(self)
        notificationHandler(subscription, Event(error: StreamCompleted.lateSubscription))
      }
    }
  }

  // MARK: Publisher

  open func updateRequest(_ requested: Int64)
  {
    precondition(requested > 0)

    var prev = CAtomicsLoad(pending, .relaxed)
    repeat {
      if prev >= requested || prev == .min { return }
    } while !CAtomicsCompareAndExchangeWeak(pending, &prev, requested, .relaxed, .relaxed)

    let additional = (requested == .max) ? .max : (requested-prev)
    processAdditionalRequest(additional)
  }

  final public func cancel(subscription: Subscription)
  {
    if !completed
    {
      queue.async {
        guard !self.completed else { return }

        let key = WeakSubscription(subscription)
        if let notificationHandler = self.observers.removeValue(forKey: key)
        {
          if self.observers.isEmpty
          {
            self.lastSubscriptionWasCanceled()
          }
          subscription.cancel(self)
          notificationHandler(subscription, Event.streamCompleted)
        }
      }
    }
  }

  // MARK: Publisher customization points

  open func processAdditionalRequest(_ additional: Int64)
  { // this is a only a customization point
    assert(additional > 0)
  }

  open func lastSubscriptionWasCanceled()
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    guard CAtomicsLoad(pending, .relaxed) > 0 else { return }
    // `pending` cannot be changed by a subscriber
    // before the current block ends.  All other ways
    // to modify `pending` must run serially on `queue`.
    // We can therefore safely store 0 here.
    CAtomicsStore(pending, 0, .relaxed)
  }

  /// Whenever a `Value` event isn't dispatched to any subscriber,
  /// we know that every remaining subscription expects zero events.
  /// When that happens, we can set `pending` back to zero.
  ///
  /// However, since these subscriptions are active, we must
  /// do so in a thread-safe way, as any of the subscriptions
  /// could `updateRequest()` at any moment.

  private func didNotNotify()
  {
    var current = CAtomicsLoad(pending, .relaxed)
    var expected = current
    repeat {
      if current < 1 || current > expected { return }
      expected = current
    } while !CAtomicsCompareAndExchangeWeak(pending, &current, 0, .relaxed, .relaxed)
  }
}


private struct WeakSubscription: Equatable, Hashable
{
  let id: UInt64
  weak var subscription: Subscription?

  init(_ s: Subscription)
  {
    subscription = s
    id = s.id
  }

  static func == (l: WeakSubscription, r: WeakSubscription) -> Bool
  {
    return (l.id == r.id) && (l.subscription == r.subscription)
  }

  func hash(into hasher: inout Hasher)
  {
    id.hash(into: &hasher)
  }
}

#if compiler(>=5.1)
extension WeakSubscription: Identifiable {}
#endif

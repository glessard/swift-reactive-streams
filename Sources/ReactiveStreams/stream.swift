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
  private var observers = Dictionary<WeakSubscription, (Event<Value>) -> Void>()

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
    case let n where n > 0: return .streaming
    case 0:                 return .waiting
    default: /* n < 0 */    fatalError()
    }
  }

  public var qos: DispatchQoS {
    return self.queue.qos
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
    } while !CAtomicsCompareAndExchange(pending, &prev, prev-1, .weak, .relaxed, .relaxed)

    for (ws, notificationHandler) in self.observers
    {
      if let subscription = ws.subscription
      {
        if subscription.shouldNotify() { notificationHandler(value) }
      }
      else
      { // subscription no longer exists: remove handler.
        self.observers.removeValue(forKey: ws)
      }
    }
  }

  /// precondition: must run on this stream's serial queue

  private func dispatchError(_ error: Event<Value>)
  {
    assert(!error.isValue)

    var prev = CAtomicsLoad(pending, .relaxed)
    repeat {
      if prev == .min { return }
    } while !CAtomicsCompareAndExchange(pending, &prev, .min, .weak, .relaxed, .relaxed)

    for (ws, notificationHandler) in self.observers
    {
      ws.subscription?.cancel(self)
      notificationHandler(error)
    }
    self.finalizeStream()
  }

  open func close()
  {
    guard !completed else { return }
    self.queue.async {
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

    self.observers.removeAll()
  }

  // subscription methods

  final public func subscribe<S: Subscriber>(_ subscriber: S)
    where S.Value == Value
  {
    subscribe(subscriptionHandler: subscriber.onSubscription) {
      [weak subscriber = subscriber] (event: Event<Value>) in
      if let subscriber = subscriber { subscriber.notify(event) }
    }
  }

  final public func subscribe<S>(substream: S) where S: SubStream<Value>
  {
    subscribe(subscriptionHandler: substream.setSubscription) {
      [weak sub = substream] (event: Event<Value>) in
      if let sub = sub { sub.queue.async { sub.dispatch(event) } }
    }
  }

  final public func subscribe<U, S>(substream: S,
                                    notificationHandler: @escaping (S, Event<Value>) -> Void)
    where S: SubStream<U>
  {
    subscribe(subscriptionHandler: substream.setSubscription) {
      [weak subscriber = substream] (event: Event<Value>) in
      if let substream = subscriber { notificationHandler(substream, event) }
    }
  }

#if swift(>=4.1.50)
  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Event<Value>) -> Void)
  {
    subscribe(subscriptionHandler: subscriptionHandler) {
      [weak subscriber = subscriber] (event: Event<Value>) in
      if let subscriber = subscriber { notificationHandler(subscriber, event) }
    }
  }
#else
  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: @escaping (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Event<Value>) -> Void)
  {
  subscribe(subscriptionHandler: subscriptionHandler) {
      [weak subscriber = subscriber] (event: Event<Value>) in
      if let subscriber = subscriber { notificationHandler(subscriber, event) }
    }
  }
#endif

  final public func subscribe(subscriptionHandler: (Subscription) -> Void,
                              notificationHandler: @escaping (Event<Value>) -> Void)
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
        notificationHandler(Event(error: StreamCompleted.lateSubscription))
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
    } while !CAtomicsCompareAndExchange(pending, &prev, requested, .weak, .relaxed, .relaxed)

    let additional = (requested == .max) ? .max : (requested-prev)
    processAdditionalRequest(additional)
  }

  open func processAdditionalRequest(_ additional: Int64)
  { // this is a only a customization point
    assert(additional > 0)
  }

  final public func cancel(subscription: Subscription)
  {
    if !completed
    {
      let key = WeakSubscription(subscription)
      queue.async {
        guard !self.completed else { return }

        if let notificationHandler = self.observers.removeValue(forKey: key)
        {
          notificationHandler(Event.streamCompleted)
        }
      }
    }
  }
}


private struct WeakSubscription: Equatable, Hashable
{
  let identifier: ObjectIdentifier
  weak var subscription: Subscription?

  init(_ s: Subscription)
  {
    subscription = s
    identifier = ObjectIdentifier(s)
  }

  static func == (l: WeakSubscription, r: WeakSubscription) -> Bool
  {
    return l.identifier == r.identifier
  }

#if swift(>=4.1.50)
  func hash(into hasher: inout Hasher)
  {
    identifier.hash(into: &hasher)
  }
#else
  var hashValue: Int { return identifier.hashValue }
#endif
}

//
//  stream.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

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
  case normally
}

public enum StreamError: Error
{
  case subscriptionFailed    // attempted to subscribe to a completed stream
}

open class EventStream<Value>: Publisher
{
  public typealias EventType = Value

  let queue: DispatchQueue
  private var observers = Dictionary<WeakSubscription, (Event<Value>) -> Void>()

  private var begun = AtomicBool()
  private var started: Bool { return begun.load(.relaxed) }

  private var pending = AtomicInt64()
  public  var requested: Int64 { return pending.load(.relaxed) }
  public  var completed: Bool  { return pending.load(.relaxed) == .min }

  public convenience init(qos: DispatchQoS = DispatchQoS.current)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", qos: qos))
  }

  public convenience init(_ queue: DispatchQueue)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", target: queue))
  }

  public init(validated queue: ValidatedQueue)
  {
    pending.initialize(0)
    begun.initialize(false)
    self.queue = queue.queue
  }

  public var state: StreamState {
    switch requested
    {
    case Int64.min:         return .ended
    case let n where n > 0: return started ? .streaming : .waiting
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
    guard !completed else { return }

    if event.isValue
    {
      dispatchValue(event)
    }
    else
    {
      dispatchError(event)
    }
  }

  /// precondition: must run on this Stream's serial queue

  final func dispatchValue(_ value: Event<Value>)
  {
    assert(value.isValue)

    var prev = pending.load(.relaxed)
    repeat {
      if prev == .max { break }
      if prev <= 0 { return }
    } while !pending.loadCAS(&prev, prev-1, .weak, .relaxed, .relaxed)

    for (ws, notificationHandler) in self.observers
    {
      if let subscription = ws.reference
      {
        if subscription.shouldNotify() { notificationHandler(value) }
      }
      else
      { // subscription no longer exists: remove handler.
        self.observers.removeValue(forKey: ws)
      }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  final func dispatchError(_ error: Event<Value>)
  {
    assert(!error.isValue)

    let prev = pending.swap(.min, .relaxed)
    if prev == .min { return }

    for notificationHandler in self.observers.values { notificationHandler(error) }
    self.finalizeStream()
  }

  open func close()
  {
    guard !completed else { return }
    self.queue.async {
      self.dispatchError(Event.streamCompleted)
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  func finalizeStream()
  {
    self.observers.removeAll()
  }

  // subscription methods

  final public func subscribe<S: Subscriber>(_ subscriber: S)
    where S.Value == Value
  {
    addSubscription(subscriptionHandler: subscriber.onSubscribe,
                    notificationHandler: {
                      [weak subscriber = subscriber] (event: Event<Value>) in
                      if let subscriber = subscriber { subscriber.notify(event) }
    })
  }

  final public func subscribe<U>(substream: SubStream<Value, U>,
                                 notificationHandler: @escaping (SubStream<Value, U>, Event<Value>) -> Void)
  {
    addSubscription(subscriptionHandler: substream.setSubscription,
                    notificationHandler: {
                      [weak subscriber = substream] (event: Event<Value>) in
                      if let substream = subscriber { notificationHandler(substream, event) }
    })
  }

  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: @escaping (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Event<Value>) -> Void)
  {
    addSubscription(subscriptionHandler: subscriptionHandler,
                    notificationHandler: {
                      [weak subscriber = subscriber] (event: Event<Value>) in
                      if let subscriber = subscriber { notificationHandler(subscriber, event) }
    })
  }

  private func addSubscription(subscriptionHandler: @escaping (Subscription) -> Void,
                               notificationHandler: @escaping (Event<Value>) -> Void)
  {
    let subscription = Subscription(source: self)

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      if started
      {
        dispatchPrecondition(condition: .notOnQueue(queue))
      }
    }
#endif

    queue.sync {
      begun.store(true, .relaxed)
      subscriptionHandler(subscription)
      if !completed
      {
        observers[WeakSubscription(subscription)] = notificationHandler
      }
      else
      {
        notificationHandler(Event(error: StreamError.subscriptionFailed))
      }
    }
  }

  // MARK: Publisher

  @discardableResult
  open func updateRequest(_ requested: Int64) -> Int64
  {
    precondition(requested > 0)

    var prev = pending.load(.relaxed)
    repeat {
      if prev >= requested || prev == .min { return 0 }
    } while !pending.loadCAS(&prev, requested, .weak, .relaxed, .relaxed)

    return (requested-prev)
  }

  final public func cancel(subscription: Subscription)
  {
    if !completed
    {
      queue.async {
        guard !self.completed else { return }
        self.performCancellation(subscription)
      }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  @discardableResult
  func performCancellation(_ subscription: Subscription) -> Bool
  {
    let key = WeakSubscription(subscription)
    guard let notificationHandler = observers.removeValue(forKey: key)
      else { fatalError("Tried to cancel an inactive subscription") }

    notificationHandler(Event.streamCompleted)
    return observers.isEmpty
  }
}


struct WeakSubscription: Equatable, Hashable
{
  let hashValue: Int
  weak var reference: Subscription?

  init(_ r: Subscription)
  {
    reference = r
    hashValue = ObjectIdentifier(r).hashValue
  }

  static func == (l: WeakSubscription, r: WeakSubscription) -> Bool
  {
    return l.hashValue == r.hashValue
  }
}

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

public enum StreamCompleted: Error, CustomStringConvertible
{
  case normally              // normal completion
  case subscriberCancelled

  public var description: String {
    switch self
    {
    case .normally:            return "Stream ended by producer"
    case .subscriberCancelled: return "Stream cancelled by subscriber"
    }
  }
}

public enum StreamError: Error
{
  case subscriptionFailed    // attempted to subscribe to a completed stream
}

open class EventStream<Value>: Publisher
{
  let queue: DispatchQueue
  private var observers = Dictionary<Subscription, (Result<Value>) -> Void>()

  private var begun = CAtomicsBoolean()
  private var started: Bool { return CAtomicsBooleanLoad(&begun, .relaxed) }

  private var pending = CAtomicsInt64()
  public  var requested: Int64 { return CAtomicsInt64Load(&pending, .relaxed) }
  public  var completed: Bool  { return CAtomicsInt64Load(&pending, .relaxed) == Int64.min }

  public convenience init(qos: DispatchQoS = DispatchQoS.current ?? .utility)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", qos: qos))
  }

  public convenience init(_ queue: DispatchQueue)
  {
    self.init(validated: ValidatedQueue(label: "eventstream", target: queue))
  }

  public init(validated queue: ValidatedQueue)
  {
    CAtomicsInt64Init(0, &pending)
    CAtomicsBooleanInit(false, &begun)
    self.queue = queue.queue
  }

  public var state: StreamState {
    if !started { return .waiting }
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

  open func dispatch(_ result: Result<Value>)
  {
    guard !completed else { return }

    switch result
    {
    case .value: dispatchValue(result)
    case .error: dispatchError(result)
    }
  }

  /// precondition: must run on this Stream's serial queue

  final func dispatchValue(_ value: Result<Value>)
  {
    assert(value.isValue)

    var prev: Int64 = 1
    while !CAtomicsInt64CAS(&prev, prev-1, &pending, .weak, .relaxed, .relaxed)
    {
      if prev == Int64.max { break }
      if prev <= 0 { return }
    }

    for (subscription, notificationHandler) in self.observers
    {
      if subscription.shouldNotify() { notificationHandler(value) }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  final func dispatchError(_ error: Result<Value>)
  {
    assert(!error.isValue)

    var prev: Int64 = 1
    while !CAtomicsInt64CAS(&prev, Int64.min, &pending, .weak, .relaxed, .relaxed)
    {
      if prev == Int64.min { return }
    }

    for notificationHandler in self.observers.values { notificationHandler(error) }
    self.finalizeStream()
  }

  open func close()
  {
    guard !completed else { return }
    self.queue.async {
      self.dispatchError(Result.error(StreamCompleted.normally))
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  func finalizeStream()
  {
    self.observers.removeAll()
  }

  // subscription methods

  final public func subscribe<O: Subscriber>(_ observer: O)
    where O.Value == Value
  {
    addSubscription(subscriptionHandler: observer.onSubscribe,
                    notificationHandler: {
                      [weak subscriber = observer] (event: Result<Value>) in
                      if let observer = subscriber { observer.notify(event) }
    })
  }

  final public func subscribe<U>(substream: SubStream<Value, U>,
                                 notificationHandler: @escaping (SubStream<Value, U>, Result<Value>) -> Void)
  {
    addSubscription(subscriptionHandler: substream.setSubscription,
                    notificationHandler: {
                      [weak subscriber = substream] (event: Result<Value>) in
                      if let substream = subscriber { notificationHandler(substream, event) }
    })
  }

  final public func subscribe<T: AnyObject>(subscriber: T,
                                            subscriptionHandler: @escaping (Subscription) -> Void,
                                            notificationHandler: @escaping (T, Result<Value>) -> Void)
  {
    addSubscription(subscriptionHandler: subscriptionHandler,
                    notificationHandler: {
                      [weak subscriber = subscriber] (event: Result<Value>) in
                      if let subscriber = subscriber { notificationHandler(subscriber, event) }
    })
  }

  private func addSubscription(subscriptionHandler: @escaping (Subscription) -> Void,
                               notificationHandler: @escaping (Result<Value>) -> Void)
  {
    let subscription = Subscription(source: self)

    func processSubscription()
    {
      subscriptionHandler(subscription)
      if !completed
      {
        observers[subscription] = notificationHandler
      }
      else
      {
        notificationHandler(Result.error(StreamError.subscriptionFailed))
      }
    }

    if !started
    { // the queue isn't running yet, no observers
      queue.sync {
        CAtomicsBooleanStore(true, &begun, .relaxed)
        processSubscription()
      }
      return
    }

    queue.async {
      processSubscription()
    }
  }

  // MARK: Publisher

  @discardableResult
  open func updateRequest(_ requested: Int64) -> Int64
  {
    precondition(requested > 0)

    var prev: Int64 = 1
    while !CAtomicsInt64CAS(&prev, requested, &pending, .weak, .relaxed, .relaxed)
    {
      if prev >= requested || prev == Int64.min { return 0 }
    }

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
    guard let notificationHandler = observers.removeValue(forKey: subscription)
      else { fatalError("Tried to cancel an inactive subscription") }

    notificationHandler(Result.error(StreamCompleted.subscriberCancelled))
    return observers.isEmpty
  }
}

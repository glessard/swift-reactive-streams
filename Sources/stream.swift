//
//  stream.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public enum StreamState { case waiting, streaming, ended }

extension StreamState: CustomStringConvertible
{
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
  case normally              // normal completion
  case subscriptionCancelled
}

public enum StreamError: Error
{
  case subscriptionFailed    // attempted to subscribe to a completed stream
}

open class EventStream<Value>: Publisher
{
  let queue: DispatchQueue
  private var observers = Dictionary<Subscription, (Result<Value>) -> Void>()

  private var started: Int32 = 0
  public private(set) var requested: Int64 = 0

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
    self.queue = queue.queue
  }

  public var state: StreamState {
    if started == 0 { return .waiting }
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
    guard requested != Int64.min else { return }

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

    var prev: Int64
    repeat {
      prev = requested
      if prev == Int64.max { break }
      if prev <= 0 { return }
    } while !OSAtomicCompareAndSwap64(prev, prev-1, &requested)

    for (subscription, notificationHandler) in self.observers
    {
      if subscription.shouldNotify() { notificationHandler(value) }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  final func dispatchError(_ error: Result<Value>)
  {
    assert(error.isError)

    var prev: Int64
    repeat {
      prev = requested
      if prev == Int64.min { return }
    } while !OSAtomicCompareAndSwap64(prev, Int64.min, &requested)

    for notificationHandler in self.observers.values { notificationHandler(error) }
    self.finalizeStream()
  }

  open func close()
  {
    guard requested != Int64.min else { return }
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

    if started == 0 && OSAtomicCompareAndSwap32(0, 1, &started)
    { // the queue isn't running yet, no observers
      queue.sync {
        assert(self.observers.isEmpty)
        subscriptionHandler(subscription)
        if self.requested != Int64.min
        {
          self.observers[subscription] = notificationHandler
        }
        else
        { // the stream was closed between the block's dispatch and its execution
          notificationHandler(Result.error(StreamError.subscriptionFailed))
        }
      }
      return
    }

    if self.requested != Int64.min
    {
      queue.async {
        subscriptionHandler(subscription)
        if self.requested != Int64.min
        {
          self.observers[subscription] = notificationHandler
        }
        else
        { // the stream was closed between the block's dispatch and its execution
          notificationHandler(Result.error(StreamError.subscriptionFailed))
        }
      }
      return
    }

    // dispatching on a queue is unnecessary in this case
    subscriptionHandler(subscription)
    notificationHandler(Result.error(StreamError.subscriptionFailed))
  }

  // MARK: Publisher

  @discardableResult
  open func updateRequest(_ requested: Int64) -> Int64
  {
    precondition(requested > 0)

    var prev: Int64
    repeat {
      prev = self.requested
      if prev >= requested || prev == Int64.min { return 0 }
    } while !OSAtomicCompareAndSwap64(prev, requested, &self.requested)

    return (requested-prev)
  }

  final public func cancel(subscription: Subscription)
  {
    if requested != Int64.min
    {
      queue.async {
        guard self.requested != Int64.min else { return }
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

    notificationHandler(Result.error(StreamCompleted.subscriptionCancelled))
    return observers.isEmpty
  }
}

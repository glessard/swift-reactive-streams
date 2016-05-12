import Dispatch

#if swift(>=3.0)
#else
public typealias ErrorProtocol = ErrorType
#endif

public enum StreamState: Int32 { case waiting = 0, streaming = 1, ended = 2 }
private let transientState = Int32.min

extension StreamState: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .waiting:   return "Stream Waiting to begin processing events"
    case .streaming: return "Stream active"
    case .ended:     return "Stream has completed"
    }
  }
}

public enum StreamCompleted: ErrorProtocol
{
  case terminated
  case didNotObserve
  case observerRemoved
}

public class Stream<Value>: Source
{
  let queue: dispatch_queue_t
  private var observers = Dictionary<Subscription, (Result<Value>) -> Void>()

  private var currentState: Int32 = 0
  internal private(set) var requested: Int64 = 0

  public convenience init(qos: qos_class_t = qos_class_self())
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true))
  }

  public convenience init(queue: dispatch_queue_t)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: false))
  }

  init(validated queue: ValidatedQueue)
  {
    self.queue = queue.queue.queue
  }

  public var state: StreamState {
    return StreamState.init(rawValue: currentState) ?? StreamState.waiting
  }

  public var qos: qos_class_t {
    return dispatch_queue_get_qos_class(self.queue, nil)
  }

  /// precondition: must run on this Source's queue

  private func dispatch(result: Result<Value>)
  {
    let state = currentState
    guard state < StreamState.ended.rawValue else { return }

    switch result
    {
    case .value:
      if requested > 0 && OSAtomicAdd64(-1, &requested) >= 0
      {
        if state == StreamState.waiting.rawValue
        {
          // this should be an unconditional atomic store
          OSAtomicCompareAndSwap32(StreamState.waiting.rawValue, StreamState.streaming.rawValue, &currentState)
        }
        for (subscription, handler) in self.observers
        {
          if subscription.shouldNotify() { handler(result) }
        }
      }

    case .error:
      // This should be an unconditional swap, with notification occuring iff the value has been changed
      if OSAtomicCompareAndSwap32(state, StreamState.ended.rawValue, &currentState)
      {
        for notificationHandler in self.observers.values { notificationHandler(result) }
        dispatch_barrier_async(self.queue) { self.finalizeStream() }
      }
    }
  }


  final func process(transformed: () -> Result<Value>?)
  {
    guard currentState < StreamState.ended.rawValue else { return }
    dispatch_async(queue) { if let result = transformed() { self.dispatch(result) } }
  }

  final public func process(result: Result<Value>)
  {
    guard currentState < StreamState.ended.rawValue else { return }
    dispatch_async(queue) { self.dispatch(result) }
  }

  final public func process(value: Value)
  {
    process(Result.value(value))
  }

  final public func process(error: ErrorProtocol)
  {
    process(Result.error(error))
  }

  public func start()
  {
    if OSAtomicCompareAndSwap32(StreamState.waiting.rawValue, StreamState.streaming.rawValue, &currentState)
    {
      dispatch_resume(queue)
    }
  }

  public func close()
  {
    guard currentState < StreamState.ended.rawValue else { return }
    dispatch_barrier_async(self.queue) {
      let state = self.currentState
      guard state < StreamState.ended.rawValue else { return }

      if OSAtomicCompareAndSwap32(state, StreamState.ended.rawValue, &self.currentState)
      {
        for notificationHandler in self.observers.values
        {
          notificationHandler(Result.error(StreamCompleted.terminated))
        }
        self.finalizeStream()
      }
    }
  }

  /// precondition: must run on a barrier block or a serial queue

  func finalizeStream()
  {
    self.observers.removeAll()
  }

  // subscription methods

  final public func subscribe(@noescape onSubscribe: (Subscription) -> Void, handler: (Subscription, Result<Value>) -> Void)
  {
    let subscription = Subscription(source: self)
    onSubscribe(subscription)
    addObserver(subscription, handler: { result in handler(subscription, result) })
  }

  final public func subscribe<O: Observer where O.EventValue == Value>(observer: O)
  {
    let subscription = Subscription(source: self)
    observer.onSubscribe(subscription)
    addObserver(subscription, handler: observer.notify)
  }

  final public func subscribe(handler: (Result<Value>) -> Void) -> Subscription
  {
    let subscription = Subscription(source: self)
    addObserver(subscription, handler: handler)
    return subscription
  }

  private func addObserver(subscription: Subscription, handler: (Result<Value>) -> Void)
  {
    if currentState == StreamState.waiting.rawValue &&
       OSAtomicCompareAndSwap32(StreamState.waiting.rawValue, transientState, &currentState)
    { // the queue isn't running yet, no observers
      assert(observers.isEmpty)
      observers[subscription] = handler
      // this should be a simple atomic store
      OSAtomicAdd32(StreamState.streaming.rawValue &- transientState, &currentState)
      assert(currentState == StreamState.streaming.rawValue)
      dispatch_resume(queue)
      return
    }

    if currentState < StreamState.ended.rawValue
    {
      dispatch_barrier_async(queue) {
        if self.currentState < StreamState.ended.rawValue
        { // duplicate additions of the same observer are dealt with trapping
          if let o = self.observers.updateValue(handler, forKey: subscription)
          {
            _ = o
            fatalError("Duplicate subscription?")
          }
        }
        else
        { // the stream was closed between the block's dispatch and its execution
          handler(Result.error(StreamCompleted.terminated))
        }
      }
      return
    }

    // dispatching on a queue is unnecessary in this case
    handler(Result.error(StreamCompleted.terminated))
  }

  // MARK: Source

  public func setRequested(requested: Int64) -> Int64
  {
    precondition(requested >= 0)
    guard currentState < StreamState.ended.rawValue else { return 0 }

    while true
    { // an atomic store wouldn't really be better
      let cur = self.requested
      if cur > requested { return 0 }
      if OSAtomicCompareAndSwap64(cur, requested, &self.requested)
      {
        return (requested-cur)
      }
    }
  }

  final public func cancel(subscription subscription: Subscription)
  {
    if currentState < StreamState.ended.rawValue
    {
      dispatch_barrier_async(queue) {
        guard self.currentState < StreamState.ended.rawValue else { return }
        guard let eventHandler = self.observers.removeValueForKey(subscription)
          else { fatalError("Tried to cancel a subscription which was not active") }

        eventHandler(Result.error(StreamCompleted.observerRemoved))
      }
    }
  }
}

extension Stream: Equatable {}

public func ==<Value>(lhs: Stream<Value>, rhs: Stream<Value>) -> Bool
{
  return lhs === rhs
}

extension Stream: Hashable
{
  public var hashValue: Int { return unsafeAddressOf(self).hashValue }
}

public class SerialStream<Value>: Stream<Value>
{
  public convenience init(qos: qos_class_t = qos_class_self())
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true))
  }

  public convenience init(queue: dispatch_queue_t)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: true))
  }

  override init(validated: ValidatedQueue)
  {
    switch validated.queue
    {
    case .serial:
      super.init(validated: validated)
    case .concurrent(let queue):
      super.init(validated: ValidatedQueue(queue: queue, serial: true))
    }
  }
}

import Dispatch

#if swift(>=3.0)
#else
public typealias ErrorProtocol = ErrorType
#endif

public enum StreamState { case waiting, streaming, ended }

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
  case normally              // normal completion
  case subscriptionFailed    // attempted to subscribe to a completed stream
  case subscriptionCancelled
}

public class Stream<Value>: Source
{
  let queue: dispatch_queue_t
  private var observers = Dictionary<Subscription, (Result<Value>) -> Void>()

  private var started: Int32 = 0
  public private(set) var requested: Int64 = 0

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
    if started == 0 { return .waiting }
    switch requested
    {
    case Int64.min:         return .ended
    case let n where n > 0: return .streaming
    case 0:                 return .waiting
    default: /* n < 0 */    fatalError()
    }
  }

  public var qos: qos_class_t {
    return dispatch_queue_get_qos_class(self.queue, nil)
  }

  /// precondition: must run on this Stream's queue

  private func dispatch(result: Result<Value>)
  {
    guard requested != Int64.min else { return }

    switch result
    {
    case .value:
      dispatchValue(result)

    case .error:
      var req = requested
      while req != Int64.min
      {
        // This should be an unconditional swap, with notification occuring iff the value has been changed
        if OSAtomicCompareAndSwap64(req, Int64.min, &requested)
        {
          for notificationHandler in self.observers.values { notificationHandler(result) }
          dispatch_barrier_async(self.queue) { self.finalizeStream() }
          break
        }
        req = requested
      }
    }
  }

  /// precondition: must run on this Stream's queue

  final func dispatchValue(value: Result<Value>)
  {
    assert(value.isValue)

    var req = requested
    while req > 0
    { // decrement iff req is not Int64.max
      if req == Int64.max || OSAtomicCompareAndSwap64(req, req-1, &requested)
      {
        for (subscription, notificationHandler) in self.observers
        {
          if subscription.shouldNotify() { notificationHandler(value) }
        }
        break
      }
      req = requested
    }
  }


  final func process(transformed: () -> Result<Value>?)
  {
    guard requested != Int64.min else { return }
    dispatch_async(queue) { if let result = transformed() { self.dispatch(result) } }
  }

  final public func process(result: Result<Value>)
  {
    guard requested != Int64.min else { return }
    dispatch_async(queue) { self.dispatch(result) }
  }

  final public func process(value: Value)
  {
    guard requested != Int64.min else { return }
    dispatch_async(self.queue) {
      guard self.requested != Int64.min else { return }
      self.dispatchValue(Result.value(value))
    }
  }

  final public func process(error: ErrorProtocol)
  {
    guard requested != Int64.min else { return }
    dispatch_barrier_async(self.queue) {
      var req = self.requested
      while req != Int64.min
      {
        // This should be an unconditional swap, with notification occuring iff the value has been changed
        if OSAtomicCompareAndSwap64(req, Int64.min, &self.requested)
        {
          let result = Result<Value>.error(error)
          for notificationHandler in self.observers.values { notificationHandler(result) }
          self.finalizeStream()
          break
        }
        req = self.requested
      }
    }
  }

  public func close()
  {
    process(StreamCompleted.normally)
  }

  /// precondition: must run on a barrier block or a serial queue

  func finalizeStream()
  {
    self.observers.removeAll()
  }

  // subscription methods

  final public func subscribe<O: Observer where O.EventValue == Value>(observer: O)
  {
    addSubscription(observer.onSubscribe, notificationHandler: observer.notify)
  }

  final public func subscribe<U>(substream: SubStream<U, Value>,
                                 notificationHandler: (Result<Value>) -> Void)
  {
    addSubscription(substream.setSubscription,
                    notificationHandler: notificationHandler)
  }

  final public func subscribe(subscriptionHandler: (Subscription) -> Void,
                              notificationHandler: (Result<Value>) -> Void)
  {
    addSubscription(subscriptionHandler,
                    notificationHandler: notificationHandler)
  }

  private func addSubscription(subscriptionHandler: (Subscription) -> Void,
                               notificationHandler: (Result<Value>) -> Void)
  {
    let subscription = Subscription(source: self)
    if started == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &started)
    { // the queue isn't running yet, no observers
      dispatch_barrier_sync(queue) {
        assert(self.observers.isEmpty)
        subscriptionHandler(subscription)
        if self.requested != Int64.min
        {
          self.observers[subscription] = notificationHandler
        }
        else
        { // the stream was closed between the block's dispatch and its execution
          notificationHandler(Result.error(StreamCompleted.subscriptionFailed))
        }
      }
      return
    }

    if self.requested != Int64.min
    {
      dispatch_barrier_async(queue) {
        subscriptionHandler(subscription)
        if self.requested != Int64.min
        {
          self.observers[subscription] = notificationHandler
        }
        else
        { // the stream was closed between the block's dispatch and its execution
          notificationHandler(Result.error(StreamCompleted.subscriptionFailed))
        }
      }
      return
    }

    // dispatching on a queue is unnecessary in this case
    subscriptionHandler(subscription)
    notificationHandler(Result.error(StreamCompleted.subscriptionFailed))
  }

  // MARK: Source

  public func updateRequest(requested: Int64) -> Int64
  {
    precondition(requested > 0)
    guard requested != Int64.min else { return 0 }

    var cur = self.requested
    while cur < requested && cur >= 0
    { // an atomic store wouldn't really be better
      if OSAtomicCompareAndSwap64(cur, requested, &self.requested)
      {
        return (requested-cur)
      }
      cur = self.requested
    }
    return 0
  }

  final public func cancel(subscription subscription: Subscription)
  {
    if requested != Int64.min
    {
      dispatch_barrier_async(queue) {
        guard self.requested != Int64.min else { return }
        guard let notificationHandler = self.observers.removeValueForKey(subscription)
          else { fatalError("Tried to cancel an inactive subscription") }

        notificationHandler(Result.error(StreamCompleted.subscriptionCancelled))
      }
    }
  }
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

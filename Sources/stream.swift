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

public enum StreamClosed: ErrorProtocol
{
  case ended
  case didNotObserve
  case observerRemoved
}

public class Stream<Value>
{
  let queue: dispatch_queue_t
  private var observers = Dictionary<UnsafePointer<Void>, (Result<Value>) -> Void>()

  private var currentState: Int32 = 0

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

  private func dispatch(result: Result<Value>)
  {
    let state = currentState
    guard state < StreamState.ended.rawValue else { return }

    switch result
    {
    case .value:
      if state == StreamState.waiting.rawValue
      {
        // this should be an unconditional atomic store
        OSAtomicCompareAndSwap32(StreamState.waiting.rawValue, StreamState.streaming.rawValue, &currentState)
      }
      for notificationHandler in self.observers.values { notificationHandler(result) }

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
          notificationHandler(Result.error(StreamClosed.ended))
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


  final public func addObserver<O: Observer where O.EventValue == Value>(observer: O)
  {
    addObserver(observer, handler: observer.notify)
  }

  final public func addObserver<U>(subStream subStream: SubStream<U, Value>, handler: (Result<Value>) -> Void)
  {
    subStream.source = self
    addObserver(subStream, handler: handler)
  }

  final public func addObserver(observer: AnyObject, handler: (Result<Value>) -> Void)
  {
    if currentState == StreamState.waiting.rawValue &&
       OSAtomicCompareAndSwap32(StreamState.waiting.rawValue, transientState, &currentState)
    { // the queue isn't running yet, no observers
      assert(observers.isEmpty)
      observers[unsafeAddressOf(observer)] = handler
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
          if let o = self.observers.updateValue(handler, forKey: unsafeAddressOf(observer))
          {
            _ = o
            fatalError("Tried to add observer which was already observing")
          }
        }
        else
        { // the stream was closed between dispatching and execution
          handler(Result.error(StreamClosed.didNotObserve))
        }
      }
      return
    }

    // dispatching on a queue is unnecessary in this case
    handler(Result.error(StreamClosed.didNotObserve))
  }

  final public func removeObserver(observer: AnyObject)
  {
    if currentState < StreamState.ended.rawValue
    {
      dispatch_barrier_async(queue) {
        guard self.currentState < StreamState.ended.rawValue else { return }
        guard let eventHandler = self.observers.removeValueForKey(unsafeAddressOf(observer))
          else { fatalError("Tried to remove an observer which was not observing") }

        eventHandler(Result.error(StreamClosed.observerRemoved))
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

public class SubStream<Value, SourceValue>: Stream<Value>
{
  private weak var source: Stream<SourceValue>? = nil

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  /// precondition: must run on a barrier block or a serial queue

  override func finalizeStream()
  {
    if let source = source
    {
      source.removeObserver(self)
      self.source = nil
    }
    super.finalizeStream()
  }
}

public class SerialSubStream<Value, SourceValue>: SubStream<Value, SourceValue>
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

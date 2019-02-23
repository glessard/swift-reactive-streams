//
//  stream-post.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

private let hptrOffset = 0
private let tptrOffset = MemoryLayout<AtomicMutableRawPointer>.stride
private let fptrOffset = MemoryLayout<AtomicMutableRawPointer>.stride*2

open class PostBox<Value>: EventStream<Value>
{
  private typealias Node = BufferNode<Event<Value>>

  private let s = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AtomicMutableRawPointer>.stride*3,
                                                   alignment: MemoryLayout<AtomicMutableRawPointer>.alignment)
  private var hptr: UnsafeMutablePointer<AtomicMutableRawPointer> {
    return (s+hptrOffset).assumingMemoryBound(to: AtomicMutableRawPointer.self)
  }
  private var head: Node {
    get { return Node(storage: CAtomicsLoad(hptr, .relaxed)) }
    set { CAtomicsStore(hptr, newValue.storage, .relaxed) }
  }
  private var tptr: UnsafeMutablePointer<AtomicMutableRawPointer> {
    return (s+tptrOffset).assumingMemoryBound(to: AtomicMutableRawPointer.self)
  }
  private var fptr: UnsafeMutablePointer<AtomicOptionalMutableRawPointer> {
    return (s+fptrOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
  }

  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)

    // set up an initial dummy node
    let node = Node.dummy
    (s+hptrOffset).bindMemory(to: AtomicMutableRawPointer.self, capacity: 2)
    CAtomicsInitialize(hptr, node.storage)
    CAtomicsInitialize(tptr, node.storage)
    (s+fptrOffset).bindMemory(to: AtomicOptionalMutableRawPointer.self, capacity: 1)
    CAtomicsInitialize(fptr, nil)
  }

  deinit {
    // empty the queue
    let head = self.head
    var next = head.next
    while let node = next
    {
      next = node.next
      node.deinitialize()
      node.deallocate()
    }

    s.deallocate()
  }

  final public var isEmpty: Bool { return CAtomicsLoad(hptr, .relaxed) == CAtomicsLoad(tptr, .relaxed) }

  final public func post(_ event: Event<Value>)
  {
    guard completed == false, CAtomicsLoad(fptr, .relaxed) == nil else { return }

    let node = Node(initializedWith: event)
    if event.isError
    {
      guard CAtomicsCompareAndExchange(fptr, nil, node.storage, .strong, .relaxed) else { return }
    }

    // events posted "simultaneously" synchronize with each other here
    let previousTailPointer = CAtomicsExchange(tptr, node.storage, .acqrel)
    let previousTail = Node(storage: previousTailPointer)

    // publish the new node to processing loop here
    CAtomicsStore(previousTail.nptr, node.storage, .release)

    if previousTailPointer == CAtomicsLoad(hptr, .relaxed)
    { // the queue had been empty or blocked
      // resume processing enqueued events
      queue.async(execute: self.processNext)
    }
  }

  final public func post(_ value: Value)
  {
    post(Event(value: value))
  }

  final public func post(_ error: Error)
  {
    post(Event(error: error))
  }

  open override func close()
  {
    post(Event.streamCompleted)
  }

  private func processNext()
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    let continueProcessing = processNext(batch: 2)
    if continueProcessing == true
    {
      queue.async(execute: self.processNext)
    }
  }

  private func processNext(batch: Int8) -> Bool
  {
    // try to dequeue the next event
    let oldHead = head
    let next = CAtomicsLoad(oldHead.nptr, .acquire)

    if requested <= 0 && CAtomicsLoad(fptr, .relaxed) != next { return false }

    if let next = Node(storage: next)
    {
      let event = next.move()
      head = next
      oldHead.deallocate()

      dispatch(event)
      return batch > 0 ? processNext(batch: batch-1) : true
    }

    // Either the queue is empty, or processing is blocked.
    // Either way, processing will resume once
    // a node has been linked after the current `head`
    return false
  }

  open override func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    // enqueue some event processing, in case stream had been paused
    queue.async(execute: self.processNext)
  }
}

private let nextOffset = 0
private let dataOffset = (MemoryLayout<AtomicOptionalMutableRawPointer>.stride + 15) & ~15

private struct BufferNode<Element>: Equatable
{
  let storage: UnsafeMutableRawPointer

  init(storage: UnsafeMutableRawPointer)
  {
    self.storage = storage
  }

  init?(storage: UnsafeMutableRawPointer?)
  {
    guard let storage = storage else { return nil }
    self.storage = storage
  }

  private init()
  {
    let size = dataOffset + MemoryLayout<Element>.stride
    storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    (storage+nextOffset).bindMemory(to: AtomicOptionalMutableRawPointer.self, capacity: 1)
    CAtomicsInitialize(nptr, nil)
    (storage+dataOffset).bindMemory(to: Element.self, capacity: 1)
  }

  static var dummy: BufferNode { return BufferNode() }

  init(initializedWith element: Element)
  {
    self.init()
    data.initialize(to: element)
  }

  func deallocate()
  {
    storage.deallocate()
  }

  var nptr: UnsafeMutablePointer<AtomicOptionalMutableRawPointer> {
    get {
      return (storage+nextOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
    }
  }

  var next: BufferNode? {
    get { return BufferNode(storage: CAtomicsLoad(nptr, .acquire)) }
  }

  private var data: UnsafeMutablePointer<Element> {
    return (storage+dataOffset).assumingMemoryBound(to: Element.self)
  }

  func deinitialize()
  {
    data.deinitialize(count: 1)
  }

  func move() -> Element
  {
    return data.move()
  }
}

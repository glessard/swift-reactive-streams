//
//  stream-post.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

open class PostBox<Value>: EventStream<Value>
{
  private typealias Node = BufferNode<Event<Value>>

  private let s = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<PostBoxState>.size,
                                                   alignment: MemoryLayout<PostBoxState>.alignment)
  private var head: UnsafeMutablePointer<AtomicMutableRawPointer> {
    return (s+headOffset).assumingMemoryBound(to: AtomicMutableRawPointer.self)
  }
  private var tail: UnsafeMutablePointer<AtomicMutableRawPointer> {
    return (s+tailOffset).assumingMemoryBound(to: AtomicMutableRawPointer.self)
  }
  private var last: UnsafeMutablePointer<AtomicOptionalMutableRawPointer> {
    return (s+lastOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
  }

  public override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)

    // set up an initial dummy node
    let node = Node.dummy
    (s+headOffset).bindMemory(to: AtomicMutableRawPointer.self, capacity: 2)
    CAtomicsInitialize(head, node.storage)
    CAtomicsInitialize(tail, node.storage)
    (s+lastOffset).bindMemory(to: AtomicOptionalMutableRawPointer.self, capacity: 1)
    CAtomicsInitialize(last, nil)
  }

  deinit {
    // empty the queue
    let head = Node(storage: CAtomicsLoad(self.head, .relaxed))
    var next = Node(storage: CAtomicsLoad(head.next, .relaxed))
    while let node = next
    {
      next = Node(storage: CAtomicsLoad(node.next, .relaxed))
      node.deinitialize()
      node.deallocate()
    }

    s.deallocate()
  }

  final public var isEmpty: Bool { return CAtomicsLoad(head, .relaxed) == CAtomicsLoad(tail, .relaxed) }

  final public func post(_ event: Event<Value>)
  {
    guard completed == false, CAtomicsLoad(last, .relaxed) == nil else { return }

    let node = Node(initializedWith: event)
    if event.isError
    {
      guard CAtomicsCompareAndExchange(last, nil, node.storage, .strong, .relaxed) else { return }
    }

    // events posted "simultaneously" synchronize with each other here
    let previousTail = Node(storage: CAtomicsExchange(tail, node.storage, .acqrel))

    // publish the new node to processing loop here
    CAtomicsStore(previousTail.next, node.storage, .release)

    if previousTail.storage == CAtomicsLoad(head, .relaxed)
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

    let requested = self.requested
    if requested <= 0 && CAtomicsLoad(last, .relaxed) == nil { return }

    // try to dequeue the next event
    let head = Node(storage: CAtomicsLoad(self.head, .acquire))
    let next = CAtomicsLoad(head.next, .acquire)

    if requested <= 0 && CAtomicsLoad(last, .relaxed) != next { return }

    if let next = next
    {
      let node = Node(storage: next)
      let event = node.move()
      CAtomicsStore(self.head, next, .release)
      head.deallocate()

      dispatch(event)
      queue.async(execute: self.processNext)
      return
    }

    // Either the queue is empty, or processing is blocked.
    // Either way, processing will resume once
    // a node has been linked after the current `head`
  }

  open override func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    // enqueue some event processing, in case stream had been paused
    queue.async(execute: self.processNext)
  }
}

private struct PostBoxState
{
  var head: AtomicMutableRawPointer
  var tail: AtomicMutableRawPointer
  var last: AtomicOptionalMutableRawPointer
}
private let headOffset = MemoryLayout.offset(of: \PostBoxState.head)!
private let tailOffset = MemoryLayout.offset(of: \PostBoxState.tail)!
private let lastOffset = MemoryLayout.offset(of: \PostBoxState.last)!

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
    let size = dataOffset + MemoryLayout<Element>.size
    storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    (storage+nextOffset).bindMemory(to: AtomicOptionalMutableRawPointer.self, capacity: 1)
    CAtomicsInitialize(next, nil)
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

  var next: UnsafeMutablePointer<AtomicOptionalMutableRawPointer> {
    return (storage+nextOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
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

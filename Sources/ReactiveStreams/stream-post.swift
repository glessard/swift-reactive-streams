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

  private var hptr: AtomicNonNullMutableRawPointer
  private var head: Node {
    get { return Node(storage: hptr.load(.relaxed)) }
    set { hptr.store(newValue.storage, .relaxed) }
  }
  private var tptr: AtomicNonNullMutableRawPointer
  private var fptr: AtomicOptionalMutableRawPointer

  override init(validated: ValidatedQueue)
  { // set up an initial dummy node
    let node = Node.dummy
    hptr = AtomicNonNullMutableRawPointer(node.storage)
    tptr = AtomicNonNullMutableRawPointer(node.storage)
    fptr = AtomicOptionalMutableRawPointer(nil)
    super.init(validated: validated)
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
    head.deallocate()
  }

  final public var isEmpty: Bool { return hptr.load(.relaxed) == tptr.load(.relaxed) }

  final public func post(_ event: Event<Value>)
  {
    guard completed == false, fptr.load(.relaxed) == nil else { return }

    let node = Node(initializedWith: event)
    if event.isError
    {
      guard fptr.CAS(nil, node.storage, .strong, .relaxed) else { return }
    }

    // events posted "simultaneously" synchronize with each other here
    let previousTailPointer = self.tptr.swap(node.storage, .acqrel)
    let previousTail = Node(storage: previousTailPointer)

    // publish the new node to processing loop here
    previousTail.nptr.store(node.storage, .release)

    if previousTailPointer == hptr.load(.relaxed)
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

    // try to dequeue the next event
    let oldHead = head
    let next = oldHead.nptr.load(.acquire)

    if requested <= 0 && fptr.load(.relaxed) != next { return }

    if let next = Node(storage: next)
    {
      let event = next.move()
      head = next
      oldHead.deallocate()

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
#if swift(>=4.1)
    storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
#else
    storage = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: 16)
#endif
    (storage+nextOffset).bindMemory(to: AtomicOptionalMutableRawPointer.self, capacity: 1)
    nptr = AtomicOptionalMutableRawPointer(nil)
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
#if swift(>=4.1)
    storage.deallocate()
#else
    let size = dataOffset + MemoryLayout<Element>.stride
    storage.deallocate(bytes: size, alignedTo: 16)
#endif
  }

  var nptr: AtomicOptionalMutableRawPointer {
    unsafeAddress {
      return UnsafeRawPointer(storage+nextOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
    }
    nonmutating unsafeMutableAddress {
      return (storage+nextOffset).assumingMemoryBound(to: AtomicOptionalMutableRawPointer.self)
    }
  }

  var next: BufferNode? {
    get { return BufferNode(storage: nptr.load(.acquire)) }
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

#if !swift(>=4.1)
  public static func ==(lhs: BufferNode, rhs: BufferNode) -> Bool
  {
    return lhs.storage == rhs.storage
  }
#endif
}

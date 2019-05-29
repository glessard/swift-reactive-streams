//
//  stream-onrequest.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

open class OnRequestStream<Value>: EventStream<Value>
{
  private var started = UnsafeMutablePointer<AtomicBool>.allocate(capacity: 1)

  private var counter = 0
  private let task: (Int) throws -> Value

  public convenience init(qos: DispatchQoS = .current, autostart: Bool = true, task: @escaping (Int) throws -> Value)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", qos: qos), autostart: autostart, task: task)
  }

  public convenience init(queue: DispatchQueue, autostart: Bool = true, task: @escaping (Int) throws -> Value)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", target: queue), autostart: autostart, task: task)
  }

  deinit {
    started.deallocate()
  }

  public init(validated queue: ValidatedQueue, autostart: Bool = true, task: @escaping (Int) throws -> Value)
  {
    CAtomicsInitialize(started, autostart)
    self.task = task
    super.init(validated: queue)
  }

  private func processNext()
  {
#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }
#endif

    if requested <= 0 { return }

    do {
      let value = try task(counter)
      dispatch(Event(value: value))
      counter += 1
      queue.async(execute: { [weak self] in self?.processNext() })
    }
    catch {
      dispatch(Event(error: error))
    }
  }

  open func start()
  {
    var streaming = CAtomicsLoad(started, .relaxed)
    repeat {
      if streaming { return }
    } while !CAtomicsCompareAndExchange(started, &streaming, true, .weak, .relaxed, .relaxed)

    queue.async(execute: self.processNext)
  }

  override open func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    if CAtomicsLoad(started, .relaxed)
    { // enqueue some event processing in case stream had been paused
      queue.async(execute: self.processNext)
    }
  }
}

extension OnRequestStream where Value == Int
{
  public convenience init(qos: DispatchQoS = .current, autostart: Bool = true)
  {
    self.init(qos: qos, autostart: autostart, task: { $0 })
  }

  public convenience init(queue: DispatchQueue, autostart: Bool = true)
  {
    self.init(queue: queue, autostart: autostart, task: { $0 })
  }
}

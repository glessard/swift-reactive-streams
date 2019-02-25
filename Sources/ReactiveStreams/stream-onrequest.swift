//
//  stream-onrequest.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

open class OnRequestStream: EventStream<Int>
{
  private var started = AtomicBool()

  private var counter = 0

  public convenience init(qos: DispatchQoS = .current, autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", qos: qos), autostart: autostart)
  }

  public convenience init(queue: DispatchQueue, autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", target: queue), autostart: autostart)
  }

  public init(validated queue: ValidatedQueue, autostart: Bool = true)
  {
    started.initialize(autostart)
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

    dispatch(Event(value: counter))
    counter += 1
    queue.async(execute: self.processNext)
  }

  open func start()
  {
    var streaming = started.load(.relaxed)
    repeat {
      if streaming { return }
    } while !started.loadCAS(&streaming, true, .weak, .relaxed, .relaxed)

    queue.async(execute: self.processNext)
  }

  override open func processAdditionalRequest(_ additional: Int64)
  {
    super.processAdditionalRequest(additional)
    if started.load(.relaxed)
    { // enqueue some event processing in case stream had been paused
      queue.async(execute: self.processNext)
    }
  }
}

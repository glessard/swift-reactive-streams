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
  private var additional = AtomicInt64()
  private var started = AtomicBool()

  private var counter = 0

  public convenience init(qos: DispatchQoS = .current, autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", qos: qos), autostart: autostart)
  }

  public convenience init(_ queue: DispatchQueue, autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(label: "onrequeststream", target: queue), autostart: autostart)
  }

  public init(validated queue: ValidatedQueue, autostart: Bool = true)
  {
    additional.initialize(0)
    started.initialize(autostart)

    super.init(validated: queue)
  }

  private func processNext()
  {
    queue.async {
      var remaining = self.additional.load(.relaxed)
      repeat {
        if remaining == 0 { return }
      } while !self.additional.loadCAS(&remaining, remaining-1, .weak, .relaxed, .relaxed)

      self.dispatch(Event(value: self.counter))
      self.counter += 1

      if remaining > 0
      { // There are events remaining; enqueue another event
        self.processNext()
      }
    }
  }

  open func start()
  {
    if started.CAS(false, true, .strong, .relaxed)
    {
      processNext()
    }
  }

  @discardableResult
  override open func updateRequest(_ requested: Int64) -> Int64
  {
    let additionalRequest = super.updateRequest(requested)
    if additionalRequest > 0
    {
      if additional.fetch_add(additionalRequest, .relaxed) == 0 &&
         started.load(.relaxed) == true
      { // There were no events remaining; enqueue another event
        processNext()
      }
    }
    return additionalRequest
  }
}

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
  private let source: DispatchSourceUserDataAdd
  private var additional = AtomicInt64()
  private var started = AtomicBool()

  public convenience init(qos: DispatchQoS? = nil, autostart: Bool = true)
  {
    let qos = qos ?? DispatchQoS.current ?? .utility
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
    source = DispatchSource.makeUserDataAddSource(queue: queue.queue)

    super.init(validated: queue)

    var counter = 0
    source.setEventHandler {
      self.dispatchValue(Event.value(counter))
      counter += 1

      if self.additional.fetch_add(-1, .relaxed) > 1
      { // There are events remaining; nudge the data source.
        self.source.add(data: 1)
      }
    }

    if autostart
    {
      source.resume()
    }
  }

  open func start()
  {
    if started.CAS(false, true, .strong, .relaxed)
    {
      source.resume()
    }
  }

  @discardableResult
  override open func updateRequest(_ requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0
    {
      if self.additional.fetch_add(additional, .relaxed) == 0
      { // There were no events remaining; nudge the data source
        self.source.add(data: 1)
      }
    }
    return additional
  }

  /// precondition: must run on a barrier block or a serial queue

  override func performCancellation(_ subscription: Subscription) -> Bool
  {
    if super.performCancellation(subscription)
    { // the event handler holds a strong reference to self; cancel it.
      source.setEventHandler(handler: nil)
      return true
    }
    return false
  }
}

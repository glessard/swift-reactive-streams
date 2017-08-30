//
//  stream-onrequest.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

open class OnRequestStream: EventStream<Int>
{
  private let source: DispatchSourceUserDataAdd
  private var additional: Int64 = 0
  private var started: Int32 = 0

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
    source = DispatchSource.makeUserDataAddSource(queue: queue.queue)
    super.init(validated: queue)

    var counter = 0
    source.setEventHandler {
      self.dispatchValue(Result.value(counter))
      counter += 1

      let updated = OSAtomicAdd64(-1, &self.additional)
      if updated > 0
      {
        // TODO: ensure 32-bit sanity
        self.source.add(data: UInt(truncatingIfNeeded: updated))
      }
    }

    if autostart
    {
      source.resume()
      started = 1
    }
  }

  open func start()
  {
    if started == 0 && OSAtomicIncrement32(&started) == 1
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
      let updated = OSAtomicAdd64(additional, &self.additional)
      if updated == additional
      {
        // TODO: ensure 32-bit sanity
        self.source.add(data: UInt(truncatingIfNeeded: updated))
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
//
//  stream-onrequest.swift
//  stream
//
//  Created by Guillaume Lessard on 20/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public class OnRequestStream: Stream<Int>
{
  private let source: dispatch_source_t
  private var additional: Int64 = 0
  private var started: Int32 = 0

  public convenience init(qos: qos_class_t = qos_class_self(), autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(qos: qos, serial: true), autostart: autostart)
  }

  public convenience init(queue: dispatch_queue_t, autostart: Bool = true)
  {
    self.init(validated: ValidatedQueue(queue: queue, serial: false), autostart: autostart)
  }

  init(validated queue: ValidatedQueue, autostart: Bool = true)
  {
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, queue.queue.queue)
    super.init(validated: queue)

    var counter = 0
    dispatch_source_set_event_handler(source) {
      self.dispatchValue(Result.value(counter))
      counter += 1

      let updated = OSAtomicAdd64Barrier(-1, &self.additional)
      if updated > 0
      {
        // TODO: ensure 32-bit sanity
        dispatch_source_merge_data(self.source, UInt(truncatingBitPattern: updated))
      }
    }

    if autostart
    {
      dispatch_resume(source)
      started = 1
    }
  }

  public func start()
  {
    if started == 0 && OSAtomicIncrement32Barrier(&started) == 1
    {
      dispatch_resume(source)
    }
  }

  override public func updateRequest(requested: Int64) -> Int64
  {
    let additional = super.updateRequest(requested)
    if additional > 0
    {
      let updated = OSAtomicAdd64Barrier(additional, &self.additional)
      if updated == additional
      {
        // TODO: ensure 32-bit sanity
        dispatch_source_merge_data(self.source, UInt(truncatingBitPattern: updated))
      }
    }
    return additional
  }

  /// precondition: must run on a barrier block or a serial queue

  override func performCancellation(subscription: Subscription) -> Bool
  {
    let unobserved = super.performCancellation(subscription)
    if unobserved
    { // the event handler holds a strong reference to self; cancel it.
      dispatch_source_set_event_handler(source) {}
    }
    return unobserved
  }
}

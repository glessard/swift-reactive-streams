//
//  stream-timer.swift
//  stream
//
//  Created by Guillaume Lessard on 7/3/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics
import struct Foundation.Date
import struct Foundation.TimeInterval

open class TimerStream: EventStream<Date>
{
  private let source: DispatchSourceTimer
  private var started = UnsafeMutablePointer<AtomicBool>.allocate(capacity: 1)
  private var startDate = Date.distantFuture

  private let timingInterval: TimeInterval
  private let timingLeeway: DispatchTimeInterval

  public init(qos: DispatchQoS = .current, interval: TimeInterval, tolerance: DispatchTimeInterval? = nil)
  {
    let queue = ValidatedQueue(label: "timerstream", qos: qos)
    timingInterval = interval
    timingLeeway = tolerance ?? .nanoseconds(0)
    source = DispatchSource.makeTimerSource(queue: queue.queue)
    CAtomicsInitialize(started, false)

    super.init(validated: queue)

    source.setEventHandler(handler: nil)
    source.resume()
  }
  
  deinit {
    started.deallocate()
  }

  @discardableResult
  open func startTimer() -> Date
  {
    var s = CAtomicsLoad(started, .relaxed)
    repeat {
      if s == true
      {
        return startDate
      }
    } while !CAtomicsCompareAndExchangeWeak(started, &s, true, .relaxed, .relaxed)

    source.suspend()
    source.setEventHandler {
      [weak stream = self] in
      if let stream = stream
      {
        stream.dispatch(Event(value: Date()))
      }
    }
    source.schedule(deadline: .now(), repeating: timingInterval, leeway: timingLeeway)

    startDate = Date()
    source.resume()
    return startDate
  }

  override open func close()
  {
    super.close()
    source.cancel()
  }
}

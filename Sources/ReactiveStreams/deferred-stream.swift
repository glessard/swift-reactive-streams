//
//  deferred-stream.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

public class DeferredStream<Value>: EventStream<Value>
{
  private var deferred: Deferred<Value>?

  convenience public init(qos: DispatchQoS? = nil, from deferred: Deferred<Value>)
  {
    let v = ValidatedQueue(label: "stream-from-deferred", qos: qos ?? deferred.qos)
    self.init(validated: v, from: deferred)
  }

  convenience public init(queue: DispatchQueue, from deferred: Deferred<Value>)
  {
    let v = ValidatedQueue(label: "stream-from-deferred", target: queue)
    self.init(validated: v, from: deferred)
  }

  private init(validated: ValidatedQueue, from deferred: Deferred<Value>)
  {
    self.deferred = deferred
    super.init(validated: validated)

    deferred.enqueue(queue: queue) {
      [weak self] event in
      guard let this = self else { return }
      this.deferred = nil
      do {
        let _ = try event.get()
        this.dispatch(event)
        this.dispatch(Event.streamCompleted)
      }
      catch {
        this.dispatch(Event(error: error))
      }
    }
  }

  open override func updateRequest(_ requested: Int64)
  { // only pass on requested updates up to and including our remaining number of events
    precondition(requested > 0)

    if deferred?.isDetermined == false
    {
      super.updateRequest(1)
    }
  }
}

extension Deferred
{
  public var eventStream: EventStream<Value> { return DeferredStream(from: self) }
}

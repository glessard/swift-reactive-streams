//
//  deferred-stream.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 9/23/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import Dispatch
import deferred

public class SingleValueStream<Value>: EventStream<Value>
{
  private var deferred: Deferred<Value>?

  public init(queue: DispatchQueue? = nil, from deferred: Deferred<Value>)
  {
    let label = "stream-from-deferred"
    let validated = queue.map({ ValidatedQueue(label: label, target: $0)}) ??
                    ValidatedQueue(label: label, qos: deferred.qos)
    self.deferred = deferred
    super.init(validated: validated)

    deferred.enqueue(queue: validated.queue) {
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

  @discardableResult
  open override func updateRequest(_ requested: Int64) -> Int64
  { // only pass on requested updates up to and including our remaining number of events
    precondition(requested > 0)

    if deferred?.isDetermined == false
    {
      return super.updateRequest(1)
    }
    return 0
  }
}

extension Deferred
{
  public var eventStream: EventStream<Value> { return SingleValueStream(from: self) }
}

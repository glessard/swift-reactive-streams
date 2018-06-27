//
//  stream-post.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

open class PostBox<Value>: EventStream<Value>
{
  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  final public func post(_ event: Event<Value>)
  {
    guard !completed else { return }
    self.queue.async {
      do {
        _ = try event.get()
        self.dispatchValue(event)
      }
      catch {
        self.dispatchError(event)
      }
    }
  }

  final public func post(_ value: Value)
  {
    guard !completed else { return }
    self.queue.async {
      self.dispatchValue(Event(value: value))
    }
  }

  final public func post(_ error: Error)
  {
    guard !completed else { return }
    self.queue.async {
      self.dispatchError(Event(error: error))
    }
  }
}

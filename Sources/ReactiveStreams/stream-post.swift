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
      self.dispatch(event)
    }
  }

  final public func post(_ value: Value)
  {
    post(Event(value: value))
  }

  final public func post(_ error: Error)
  {
    post(Event(error: error))
  }
}

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

  final public func post(_ result: Result<Value>)
  {
    guard requested != Int64.min else { return }
    self.queue.async {
      switch result {
      case .value: self.dispatchValue(result)
      case .error: self.dispatchError(result)
      }
    }
  }

  final public func post(_ value: Value)
  {
    guard requested != Int64.min else { return }
    self.queue.async {
      self.dispatchValue(Result.value(value))
    }
  }

  final public func post(_ error: Error)
  {
    guard requested != Int64.min else { return }
    self.queue.async {
      self.dispatchError(Result.error(error))
    }
  }
}

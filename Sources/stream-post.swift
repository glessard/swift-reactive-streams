//
//  stream-post.swift
//  stream
//
//  Created by Guillaume Lessard on 31/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public class PostBox<Value>: Stream<Value>
{
  override init(validated: ValidatedQueue)
  {
    super.init(validated: validated)
  }

  final public func post(result: Result<Value>)
  {
    guard requested != Int64.min else { return }
    dispatch_async(self.queue) {
      self.dispatch(result)
    }
  }

  final public func post(value: Value)
  {
    guard requested != Int64.min else { return }
    dispatch_async(self.queue) {
      self.dispatchValue(Result.value(value))
    }
  }

  final public func post(error: ErrorProtocol)
  {
    guard requested != Int64.min else { return }
    dispatch_barrier_async(self.queue) {
      self.dispatchError(Result.error(error))
    }
  }
}

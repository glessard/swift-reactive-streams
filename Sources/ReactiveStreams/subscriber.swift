//
//  subscriber.swift
//  stream
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public protocol Subscriber: class
{
  associatedtype Value

  func onSubscribe(_ subscription: Subscription)
  func onValue(_ value: Value)
  func onError(_ error: Error)
  func onCompletion(_ status: StreamCompleted)
}

extension Subscriber
{
  func notify(_ result: Result<Value>)
  {
    switch result
    {
    case .value(let value):
      self.onValue(value)
    case .error(let closed as StreamCompleted):
      self.onCompletion(closed)
    case .error(let error):
      self.onError(error)
    }
  }
}

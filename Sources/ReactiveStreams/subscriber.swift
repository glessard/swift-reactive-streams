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

  func onSubscription(_ subscription: Subscription)
  func onValue(_ value: Value)
  func onError(_ error: Error)
  func onCompletion()
}

extension Subscriber
{
  func onEvent(_ event: Event<Value>)
  {
    switch event.state
    {
    case .success(let value)?: self.onValue(value)
    case .failure(let error)?: self.onError(error)
    case nil:                  self.onCompletion()
    }
  }
}

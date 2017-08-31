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
  func notify(_ event: Event<Value>)
  {
    do {
      self.onValue(try event.getValue())
    }
    catch let final as StreamCompleted {
      self.onCompletion(final)
    }
    catch {
      self.onError(error)
    }
  }
}

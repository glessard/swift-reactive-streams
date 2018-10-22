//
//  publisher.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public protocol EventSource: class
{
  func updateRequest(_ requested: Int64)
  func cancel(subscription: Subscription)
}

public protocol Publisher: EventSource
{
  associatedtype EventType

  func subscribe<S: Subscriber>(_ subscriber: S) where S.Value == EventType

  func subscribe<T: AnyObject, Value>(subscriber: T,
                                      subscriptionHandler: @escaping (Subscription) -> Void,
                                      notificationHandler: @escaping (T, Event<Value>) -> Void) where Value == EventType
}

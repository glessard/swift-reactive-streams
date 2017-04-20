//
//  notifier.swift
//  stream
//
//  Created by Guillaume Lessard on 25/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

open class Notifier<Target: AnyObject, Value>
{
  fileprivate weak var target: Target?
  fileprivate let notificationHandler: (Target, Result<Value>) -> Void

  public init(target: Target, handler: @escaping (Target, Result<Value>) -> Void)
  {
    self.target = target
    notificationHandler = handler
  }

  open func notify(_ event: Result<Value>)
  {
    if let target = target
    {
      notificationHandler(target, event)
    }
  }
}

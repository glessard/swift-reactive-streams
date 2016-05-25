//
//  notifier.swift
//  stream
//
//  Created by Guillaume Lessard on 25/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public class Notifier<Target: AnyObject, Value>
{
  private weak var target: Target?
  private let notificationHandler: (Target, Result<Value>) -> Void

  public init(target: Target, handler: (Target, Result<Value>) -> Void)
  {
    self.target = target
    notificationHandler = handler
  }

  public func notify(event: Result<Value>)
  {
    if let target = target
    {
      notificationHandler(target, event)
    }
  }
}

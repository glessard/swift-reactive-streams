//
//  observer.swift
//  stream
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public protocol Observer: class
{
  associatedtype EventValue

  func notify(result: Result<EventValue>)
  func notify(value value: EventValue)
  func notify(error error: ErrorType)
}

extension Observer
{
  public func notify(value value: EventValue)
  {
    notify(Result.value(value))
  }

  public func notify(error error: ErrorType)
  {
    notify(Result.error(error))
  }
}

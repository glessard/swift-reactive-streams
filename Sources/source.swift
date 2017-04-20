//
//  source.swift
//  stream
//
//  Created by Guillaume Lessard on 11/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

public protocol Source: class
{
  @discardableResult func updateRequest(_ requested: Int64) -> Int64
  func cancel(subscription: Subscription)
}

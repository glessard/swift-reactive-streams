//
//  event.swift
//  ReactiveStreams
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Outcome

public typealias Event = Outcome

extension Event
{
  public init(final: StreamCompleted)
  {
    self.init(error: final)
  }

  public static var streamCompleted: Event<Value> {
    return Event(final: StreamCompleted.normally)
  }

  public var streamCompleted: StreamCompleted? {
    return self.error as? StreamCompleted
  }

  public var streamError: Error? {
    if let error = error, !(error is StreamCompleted)
    { return error }

    return nil
  }
}

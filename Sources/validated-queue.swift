//
//  validated-queue.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct ValidatedQueue
{
  var queue: DispatchQueue

  init(qos: DispatchQoS = DispatchQoS.current())
  {
    self.queue = DispatchQueue(label: "serial-queue", qos: qos)
  }

  init(_ queue: DispatchQueue)
  {
    self.queue = DispatchQueue(label: "dependent-queue", target: queue)
  }
}

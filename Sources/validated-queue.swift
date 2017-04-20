//
//  validated-queue.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

enum TypedQueue
{
  case serial(DispatchQueue)
  case concurrent(DispatchQueue)

  var queue: DispatchQueue {
    switch self
    {
    case .serial(let queue):     return queue
    case .concurrent(let queue): return queue
    }
  }
}

struct ValidatedQueue
{
  var queue: TypedQueue

  init(qos: DispatchQoS = DispatchQoS.current(), serial: Bool)
  {
    if serial
    {
      let validated = DispatchQueue(label: "serial-queue", qos: qos)
      self.queue = TypedQueue.serial(validated)
    }
    else
    {
      let validated = DispatchQueue(label: "concurrent-queue", qos: qos, attributes: DispatchQueue.Attributes.concurrent)
      self.queue = TypedQueue.serial(validated)
    }
  }

  init(queue: DispatchQueue, serial: Bool)
  {
    if serial
    { // create a new queue whose target will be the queue that's passed in
      // this is necessary since we can't know whether the parameter is a concurrent queue
      let validated = DispatchQueue(label: "serial-queue", target: queue)
      self.queue = TypedQueue.serial(validated)
    }
    else
    { // create a new queue whose target will be the queue that's passed in
      // this is necessary since barrier blocks don't work on the global concurrent queues
      let validated = DispatchQueue(label: "concurrent-queue", attributes: DispatchQueue.Attributes.concurrent, target: queue)
      self.queue = TypedQueue.concurrent(validated)
    }
  }
}

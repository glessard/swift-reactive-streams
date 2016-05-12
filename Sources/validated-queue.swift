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
  case serial(dispatch_queue_t)
  case concurrent(dispatch_queue_t)

  var queue: dispatch_queue_t {
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

  init(qos: qos_class_t = qos_class_self(), serial: Bool)
  {
    if serial
    {
      let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)
      let validated = dispatch_queue_create("serial-queue", attr)
      dispatch_suspend(validated)
      self.queue = TypedQueue.serial(validated)
    }
    else
    {
      let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, qos, 0)
      let validated = dispatch_queue_create("concurrent-queue", attr)
      dispatch_suspend(validated)
      self.queue = TypedQueue.serial(validated)
    }
  }

  init(queue: dispatch_queue_t, serial: Bool)
  {
    if serial
    { // create a new queue whose target will be the queue that's passed in
      // this is necessary since we can't know whether the parameter is a concurrent queue
      let validated = dispatch_queue_create("serial-queue", DISPATCH_QUEUE_SERIAL)
      dispatch_suspend(validated)
      dispatch_set_target_queue(validated, queue)
      self.queue = TypedQueue.serial(validated)
    }
    else
    { // create a new queue whose target will be the queue that's passed in
      // this is necessary since barrier blocks don't work on the global concurrent queues
      let validated = dispatch_queue_create("concurrent-queue", DISPATCH_QUEUE_CONCURRENT)
      dispatch_suspend(validated)
      dispatch_set_target_queue(validated, queue)
      self.queue = TypedQueue.concurrent(validated)
    }
  }
}
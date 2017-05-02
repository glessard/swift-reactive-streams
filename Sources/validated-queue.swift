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

  init(label: String, qos: DispatchQoS = DispatchQoS.current ?? .utility)
  {
    self.queue = DispatchQueue(label: label+"\(qos.qosClass.rawValue)", qos: qos)
  }

  init(label: String, target: DispatchQueue)
  {
    self.queue = DispatchQueue(label: label+"-"+target.label, target: target)
  }
}

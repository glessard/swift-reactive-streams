//
//  validated-queue.swift
//  stream
//
//  Created by Guillaume Lessard on 06/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

public struct ValidatedQueue
{
  let queue: DispatchQueue

  public init(label: String, qos: DispatchQoS = .current)
  {
#if swift(>=4.2) && os(Linux)
    // workaround for <https://bugs.swift.org/browse/SR-8906>
    self.queue = DispatchQueue(label: label, qos: qos)
#else
    self.queue = DispatchQueue(label: label+"-\(qos.qosClass)", qos: qos)
#endif
  }

  public init(label: String, target: DispatchQueue)
  {
    self.queue = DispatchQueue(label: label+"-"+target.label, target: target)
  }
}

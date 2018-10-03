//
//  dispatch-utilities.swift
//  stream
//
//  Created by Guillaume Lessard on 13/02/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

// these extensions could be a separate module, but why bother

extension DispatchQoS
{
  static public var current: DispatchQoS
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    guard let qosClass = DispatchQoS.QoSClass(rawValue: qos_class_self())
      else { return .default }
    return DispatchQoS(qosClass: qosClass, relativePriority: 0)
#else // platforms that rely on swift-corelibs-libdispatch
    return .default
#endif
  }
}

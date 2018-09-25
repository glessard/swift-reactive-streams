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
    guard let qosClass = DispatchQoS.QoSClass.current else { return .default }
    return DispatchQoS(qosClass: qosClass, relativePriority: 0)
  }
}

extension DispatchQoS.QoSClass
{
  static var current: DispatchQoS.QoSClass?
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    return DispatchQoS.QoSClass(rawValue: qos_class_self())
#else // platforms that rely on swift-corelibs-libdispatch
    return nil
#endif
  }
}

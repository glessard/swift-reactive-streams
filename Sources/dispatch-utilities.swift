//
//  dispatch-utilities.swift
//  stream
//
//  Created by Guillaume Lessard on 13/02/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

// these extensions could be a separate module, but why bother

extension DispatchTimeInterval
{
  var seconds: Double {
    @inline(__always)
    get {
      switch self
      {
      case .nanoseconds(let ns):  return Double(ns)*1e-9
      case .microseconds(let µs): return Double(µs)*1e-6
      case .milliseconds(let ms): return Double(ms)*1e-3
      case .seconds(let seconds): return Double(seconds)
      }
    }
  }
}

extension DispatchQoS
{
  static var current: DispatchQoS?
  {
    if let qosClass = DispatchQoS.QoSClass.current
    {
      return DispatchQoS(qosClass: qosClass, relativePriority: 0)
    }
    return nil
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

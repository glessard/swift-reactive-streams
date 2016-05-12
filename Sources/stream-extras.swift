//
//  stream-extras.swift
//  stream
//
//  Created by Guillaume Lessard on 03/05/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension Stream
{
  private func map<U>(mapped: SubStream<U, Value>, transform: (Value) throws -> U) -> Stream<U>
  {
    self.addObserver(subStream: mapped) { result in mapped.process { result.map(transform) } }
    return mapped
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<U, Value>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Value) throws -> U) -> Stream<U>
  {
    return map(SubStream<U, Value>(queue: queue), transform: transform)
  }
}

extension Stream
{
  private func map<U>(mapped: SubStream<U, Value>, transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    self.addObserver(subStream: mapped) { result in mapped.process { transform(result) } }
    return mapped
  }

  public func map<U>(qos qos: qos_class_t = qos_class_self(), transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<U, Value>(qos: qos), transform: transform)
  }

  public func map<U>(queue queue: dispatch_queue_t, transform: (Result<Value>) -> Result<U>) -> Stream<U>
  {
    return map(SubStream<U, Value>(queue: queue), transform: transform)
  }
}

extension Stream
{
  private func last(mapped: SerialSubStream<Value, Value>) -> Stream<Value>
  {
    var last = Result<Value>()
    self.addObserver(subStream: mapped) {
      result in
      mapped.process {
        switch result
        {
        case .value:
          last = result
        case .error:
          if case .value = last
          {
            mapped.process(last)
          }
          mapped.process(result)
        }
        return nil
      }
    }
    return mapped
  }

  public func last(qos qos: qos_class_t = qos_class_self()) -> Stream<Value>
  {
    return last(SerialSubStream<Value, Value>(qos: qos))
  }

  public func last(queue queue: dispatch_queue_t) -> Stream<Value>
  {
    return last(SerialSubStream<Value, Value>(queue: queue))
  }
}

extension Stream
{
  public func notify(qos qos: qos_class_t = qos_class_self(), task: (Result<Value>) -> Void)
  {
    notify(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify(queue queue: dispatch_queue_t, task: (Result<Value>) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.addObserver(local) {
      result in
      dispatch_async(local) { task(result) }
    }
  }
}

extension Stream
{
  public func onValue(qos qos: qos_class_t = qos_class_self(), task: (Value) -> Void)
  {
    onValue(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onValue(queue queue: dispatch_queue_t, task: (Value) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.addObserver(local) {
      result in
      if case .value(let value) = result
      {
        dispatch_async(local) { task(value) }
      }
    }
  }
}

extension Stream
{
  public func onError(qos qos: qos_class_t = qos_class_self(), task: (ErrorType) -> Void)
  {
    onError(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onError(queue queue: dispatch_queue_t, task: (ErrorType) -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.addObserver(local) {
      result in
      if case .error(let error) = result
      {
        dispatch_async(local) { task(error) }
      }
    }
  }
}

extension Stream
{
  public func onEnd(qos qos: qos_class_t = qos_class_self(), task: () -> Void)
  {
    onEnd(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onEnd(queue queue: dispatch_queue_t, task: () -> Void)
  {
    let local = dispatch_queue_create("local-notify-queue", DISPATCH_QUEUE_CONCURRENT)
    dispatch_set_target_queue(local, queue)
    self.addObserver(local) {
      result in
      if case .error(let error) = result where error is StreamClosed
      {
        dispatch_async(local) { task() }
      }
    }
  }
}

extension Stream
{
  private func next(mapped: SerialSubStream<Value, Value>, count: Int) -> Stream<Value>
  {
    var i: Int64 = 0
    let c = Int64(count)
    self.addObserver(subStream: mapped) {
      result in
      mapped.process {
        switch OSAtomicIncrement64(&i)
        {
        case let v where v < c:
          return result
        case c:
          mapped.process(result)
          mapped.close()
          return nil
        default:
          return nil
        }
      }
    }
    return mapped
  }

  public func next(qos qos: qos_class_t = qos_class_self(), count: Int = 1) -> Stream<Value>
  {
    return next(SerialSubStream<Value, Value>(qos: qos), count: count)
  }

  public func next(queue queue: dispatch_queue_t, count: Int = 1) -> Stream<Value>
  {
    return next(SerialSubStream<Value, Value>(queue: queue), count: count)
  }
}

extension Stream
{
  private func reduce<U>(mapped: SerialSubStream<U, Value>, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    var current = initial
    self.addObserver(subStream: mapped) {
      result in
      mapped.process {
        switch result
        {
        case .value(let value):
          do {
            current = try transform(current, value)
          }
          catch {
            return Result.error(error)
          }
        case .error(let error) where error is StreamClosed:
          mapped.process(current)
          mapped.process(error)
        case .error(let error):
          mapped.process(error)
          // return Result.error(error)
        }
        return nil
      }
    }
    return mapped
  }

  public func reduce<U>(initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(SerialSubStream<U, Value>(qos: qos_class_self()), initial: initial, transform: transform)
  }

  public func reduce<U>(qos qos: qos_class_t, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(SerialSubStream<U, Value>(qos: qos), initial: initial, transform: transform)
  }

  public func reduce<U>(queue queue: dispatch_queue_t, initial: U, transform: (U, Value) throws -> U) -> Stream<U>
  {
    return reduce(SerialSubStream<U, Value>(queue: queue), initial: initial, transform: transform)
  }
}

extension Stream
{
  private func countEvents(mapped: SerialSubStream<Int, Value>) -> Stream<Int>
  {
    return reduce(mapped, initial: 0, transform: { c,_ in c+1 })
  }

  public func countEvents(qos qos: qos_class_t = qos_class_self()) -> Stream<Int>
  {
    return countEvents(SerialSubStream<Int, Value>(qos: qos))
  }

  public func countEvents(queue queue: dispatch_queue_t) -> Stream<Int>
  {
    return countEvents(SerialSubStream<Int, Value>(queue: queue))
  }
}

extension Stream
{
  private func coalesce(mapped: SerialSubStream<[Value], Value>) -> Stream<[Value]>
  {
    var current = [Value]()
    self.addObserver(subStream: mapped) {
      result in
      mapped.process {
        switch result
        {
        case .value(let value):
          current.append(value)
        case .error(let error) where error is StreamClosed:
          mapped.process(current)
          mapped.process(error)
        case .error(let error):
          mapped.process(error)
          // return Result.error(error)
        }
        return nil
      }
    }
    return mapped
  }

  public func coalesce(qos qos: qos_class_t = qos_class_self()) -> Stream<[Value]>
  {
    return coalesce(SerialSubStream<[Value], Value>(qos: qos))
  }

  public func coalesce(queue queue: dispatch_queue_t) -> Stream<[Value]>
  {
    return coalesce(SerialSubStream<[Value], Value>(queue: queue))
  }
}

extension Stream
{
  public func split(qos: qos_class_t = qos_class_self()) -> (Stream<Value>, Stream<Value>)
  {
    let s1 = Stream<Value>()
    let s2 = Stream<Value>()
    self.addObserver(s1) {
      result in
      s1.process(result)
      s2.process(result)
    }
    return (s1,s2)
  }

  public func split(qos: qos_class_t = qos_class_self(), count: Int) -> [Stream<Value>]
  {
    precondition(count >= 0)
    guard count > 0 else { return [Stream<Value>]() }

    let streams = (0..<count).map { _ in Stream<Value>() }
    self.addObserver(streams[0]) {
      result in
      streams.forEach({ $0.process(result) })
    }
    return streams
  }
}

extension Stream
{
  private func flatMap<U>(merged: MergeStream<U>, transform: (Value) -> Stream<U>) -> Stream<U>
  {
    self.addObserver(merged) {
      result in
      merged.process {
        switch result
        {
        case .value(let value):
          merged.merge(transform(value))
        case .error(_ as StreamClosed):
          merged.close()
        case .error(let error):
          merged.process(error)
        }
        return nil
      }
    }
    return merged
  }

  public func flatMap<U>(queue queue: dispatch_queue_t, transform: (Value) -> Stream<U>) -> Stream<U>
  {
    return flatMap(MergeStream(queue: queue), transform: transform)
  }

  public func flatMap<U>(qos qos: qos_class_t = qos_class_self(), transform: (Value) -> Stream<U>) -> Stream<U>
  {
    return flatMap(MergeStream(qos: qos), transform: transform)
  }
}

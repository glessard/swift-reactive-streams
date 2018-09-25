//
//  TestError.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-09-24.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

enum TestError: Error, Equatable
{
  case value(Int)

  var error: Int {
    switch self { case .value(let v): return v }
  }

  init(_ e: Int = 0) { self = .value(e) }
}

func == (l: TestError, r: TestError) -> Bool
{
  switch (l,r)
  {
  case let (.value(lv), .value(rv)): return lv == rv
  }
}

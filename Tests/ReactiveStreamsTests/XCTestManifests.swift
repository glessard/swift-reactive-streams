import XCTest

extension DeferredOperationsTests {
    static let __allTests = [
        ("testFinalOutcome", testFinalOutcome),
        ("testNext", testNext),
    ]
}

extension DeferredStreamTests {
    static let __allTests = [
        ("testDeferredStreamAlreadyDetermined", testDeferredStreamAlreadyDetermined),
        ("testDeferredStreamWithError", testDeferredStreamWithError),
        ("testDeferredStreamWithValue", testDeferredStreamWithValue),
    ]
}

extension SingleValueSubscriberTests {
    static let __allTests = [
        ("testSingleValueSubscriberCancelled", testSingleValueSubscriberCancelled),
        ("testSingleValueSubscriberWithError", testSingleValueSubscriberWithError),
        ("testSingleValueSubscriberWithValue", testSingleValueSubscriberWithValue),
    ]
}

extension eventTests {
    static let __allTests = [
        ("testGetters", testGetters),
    ]
}

extension flatMapTests {
    static let __allTests = [
        ("testFlatMap1", testFlatMap1),
        ("testFlatMap2", testFlatMap2),
        ("testFlatMap3", testFlatMap3),
        ("testFlatMap4", testFlatMap4),
        ("testFlatMap5", testFlatMap5),
        ("testFlatMap6", testFlatMap6),
        ("testFlatMap7", testFlatMap7),
        ("testFlatMap8", testFlatMap8),
    ]
}

extension mergeTests {
    static let __allTests = [
        ("testMerge1", testMerge1),
        ("testMerge2", testMerge2),
        ("testMerge3", testMerge3),
        ("testMerge4", testMerge4),
        ("testMerge5", testMerge5),
        ("testMerge6", testMerge6),
        ("testMerge7", testMerge7),
        ("testMerge8", testMerge8),
        ("testMergeDelayingError1", testMergeDelayingError1),
        ("testMergeDelayingError2", testMergeDelayingError2),
    ]
}

extension onRequestTests {
    static let __allTests = [
        ("testOnRequest1", testOnRequest1),
        ("testOnRequest2", testOnRequest2),
        ("testOnRequest3", testOnRequest3),
    ]
}

extension streamTests {
    static let __allTests = [
        ("testCoalesce", testCoalesce),
        ("testCountEvents", testCountEvents),
        ("testFinal1", testFinal1),
        ("testFinal2", testFinal2),
        ("testFinal3", testFinal3),
        ("testLifetime1", testLifetime1),
        ("testLifetime2", testLifetime2),
        ("testLifetime3", testLifetime3),
        ("testLifetime4", testLifetime4),
        ("testMap1", testMap1),
        ("testMap2", testMap2),
        ("testMap3", testMap3),
        ("testNextN", testNextN),
        ("testNextTruncated", testNextTruncated),
        ("testNotify", testNotify),
        ("testOnComplete", testOnComplete),
        ("testOnError", testOnError),
        ("testOnValue", testOnValue),
        ("testPaused1", testPaused1),
        ("testPaused2", testPaused2),
        ("testPaused3", testPaused3),
        ("testPost", testPost),
        ("testReduce1", testReduce1),
        ("testReduce2", testReduce2),
        ("testReduceEmptyStream", testReduceEmptyStream),
        ("testSkipN", testSkipN),
        ("testSplit0", testSplit0),
        ("testSplit1", testSplit1),
        ("testSplit2", testSplit2),
        ("testSplit3", testSplit3),
        ("testSplit4", testSplit4),
        ("testSplit5", testSplit5),
        ("testStreamState", testStreamState),
    ]
}

extension subscriberTests {
    static let __allTests = [
        ("testSubscriber1", testSubscriber1),
        ("testSubscriber2", testSubscriber2),
    ]
}

extension timerTests {
    static let __allTests = [
        ("testTimerCreation", testTimerCreation),
        ("testTimerTiming", testTimerTiming),
        ("testUnusedTimer", testUnusedTimer),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DeferredOperationsTests.__allTests),
        testCase(DeferredStreamTests.__allTests),
        testCase(SingleValueSubscriberTests.__allTests),
        testCase(eventTests.__allTests),
        testCase(flatMapTests.__allTests),
        testCase(mergeTests.__allTests),
        testCase(onRequestTests.__allTests),
        testCase(streamTests.__allTests),
        testCase(subscriberTests.__allTests),
        testCase(timerTests.__allTests),
    ]
}
#endif

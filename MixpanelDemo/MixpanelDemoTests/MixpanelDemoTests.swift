//
//  MixpanelDemoTests.swift
//  MixpanelDemoTests
//
//  Created by Yarden Eitan on 6/5/16.
//  Copyright © 2016 Mixpanel. All rights reserved.
//

import XCTest
import Nocilla

@testable import Mixpanel
@testable import MixpanelDemo

class MixpanelDemoTests: MixpanelBaseTests {

    func test5XXResponse() {
        _ = stubTrack().andReturn(503)
        
        mixpanel.track(event: "Fake Event")

        mixpanel.flush()
        waitForSerialQueue()

        mixpanel.flush()
        waitForSerialQueue()

        // Failure count should be 3
        let waitTime =
            mixpanel.flushInstance.networkRequestsAllowedAfterTime - Date().timeIntervalSince1970
        print("Delta wait time is \(waitTime)")
        XCTAssert(waitTime >= 120, "Network backoff time is less than 2 minutes.")
        XCTAssert(mixpanel.flushInstance.networkConsecutiveFailures == 2,
                  "Network failures did not equal 2")
        XCTAssert(mixpanel.eventsQueue.count == 1,
                  "Removed an event from the queue that was not sent")
    }

    func testRetryAfterHTTPHeader() {
        _ = stubTrack().andReturn(200)?.withHeader("Retry-After", "60")

        mixpanel.track(event: "Fake Event")

        mixpanel.flush()
        waitForSerialQueue()

        mixpanel.flush()
        waitForSerialQueue()

        // Failure count should be 3
        let waitTime =
            mixpanel.flushInstance.networkRequestsAllowedAfterTime - Date().timeIntervalSince1970
        print("Delta wait time is \(waitTime)")
        XCTAssert(fabs(60 - waitTime) < 5, "Mixpanel did not respect 'Retry-After' HTTP header")
        XCTAssert(mixpanel.flushInstance.networkConsecutiveFailures == 0,
                  "Network failures did not equal 0")
    }

    func testFlushEvents() {
        stubTrack()

        mixpanel.identify(distinctId: "d1")
        for i in 0..<50 {
            mixpanel.track(event: "event \(i)")
        }

        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "events should have been flushed")

        for i in 0..<60 {
            mixpanel.track(event: "evemt \(i)")
        }

        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "events should have been flushed")
    }


    func testFlushPeople() {
        stubEngage()

        mixpanel.identify(distinctId: "d1")
        for i in 0..<50 {
            mixpanel.people.set(property: "p1", to: "\(i)")
        }

        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.peopleQueue.count == 0, "people should have been flushed")
        for i in 0..<60 {
            mixpanel.people.set(property: "p1", to: "\(i)")
        }
        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.peopleQueue.count == 0, "people should have been flushed")
    }

    func testFlushNetworkFailure() {
        stubTrack().andFailWithError(
            NSError(domain: "com.mixpanel.sdk.testing", code: 1, userInfo: nil))
        mixpanel.identify(distinctId: "d1")
        for i in 0..<50 {
            mixpanel.track(event: "event \(UInt(i))")
        }
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 50, "50 events should be queued up")
        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 50,
                      "events should still be in the queue if flush fails")
    }

    func testAddingEventsAfterFlush() {
        stubTrack()
        mixpanel.identify(distinctId: "d1")
        for i in 0..<10 {
            mixpanel.track(event: "event \(UInt(i))")
        }
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 10, "10 events should be queued up")
        mixpanel.flush()
        for i in 0..<5 {
            mixpanel.track(event: "event \(UInt(i))")
        }
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 5, "5 more events should be queued up")
        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0, "events should have been flushed")
    }

    func testDropEvents() {
        mixpanel.delegate = self
        var events = Queue()
        for i in 0..<5000 {
            events.append(["i": i])
        }
        mixpanel.eventsQueue = events
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 5000)
        for i in 0..<5 {
            mixpanel.track(event: "event", properties: ["i": 5000 + i])
        }
        waitForSerialQueue()
        var e: Properties = mixpanel.eventsQueue.last!
        XCTAssertTrue(mixpanel.eventsQueue.count == 5000)
        XCTAssertEqual(e["properties"]?["i"], 5004)
    }

    func testIdentify() {
        for _ in 0..<2 {
            // run this twice to test reset works correctly wrt to distinct ids
            let distinctId: String = "d1"
            // try this for IFA, ODIN and nil
            XCTAssertEqual(mixpanel.distinctId,
                           mixpanel.defaultDistinctId(),
                           "mixpanel identify failed to set default distinct id")
            XCTAssertNil(mixpanel.people.distinctId,
                         "mixpanel people distinct id should default to nil")
            mixpanel.track(event: "e1")
            waitForSerialQueue()
            XCTAssertTrue(mixpanel.eventsQueue.count == 1,
                          "events should be sent right away with default distinct id")
            XCTAssertEqual(mixpanel.eventsQueue.last?["properties"]?["distinct_id"],
                           mixpanel.defaultDistinctId(),
                           "events should use default distinct id if none set")
            mixpanel.people.set(property: "p1", to: "a")
            waitForSerialQueue()
            XCTAssertTrue(mixpanel.peopleQueue.count == 0,
                          "people records should go to unidentified queue before identify:")
            XCTAssertTrue(mixpanel.people.unidentifiedQueue.count == 1,
                          "unidentified people records not queued")
            XCTAssertEqual(mixpanel.people.unidentifiedQueue.last?["$token"] as? String,
                           kTestToken,
                           "incorrect project token in people record")
            mixpanel.identify(distinctId: distinctId)
            waitForSerialQueue()
            XCTAssertEqual(mixpanel.distinctId, distinctId,
                           "mixpanel identify failed to set distinct id")
            XCTAssertEqual(mixpanel.people.distinctId, distinctId,
                           "mixpanel identify failed to set people distinct id")
            XCTAssertTrue(mixpanel.people.unidentifiedQueue.count == 0,
                          "identify: should move records from unidentified queue")
            XCTAssertTrue(mixpanel.peopleQueue.count == 1,
                          "identify: should move records to main people queue")
            XCTAssertEqual(mixpanel.peopleQueue.last?["$token"] as? String,
                           kTestToken, "incorrect project token in people record")
            XCTAssertEqual(mixpanel.peopleQueue.last?["$distinct_id"] as? String,
                           distinctId, "distinct id not set properly on unidentified people record")
            var p: Properties = mixpanel.peopleQueue.last?["$set"] as! Properties
            XCTAssertEqual(p["p1"] as? String, "a", "custom people property not queued")
            assertDefaultPeopleProperties(p)
            mixpanel.people.set(property: "p1", to: "a")
            waitForSerialQueue()
            XCTAssertTrue(mixpanel.people.unidentifiedQueue.count == 0,
                          "once idenitfy: is called, unidentified queue should be skipped")
            XCTAssertTrue(mixpanel.peopleQueue.count == 2,
                          "once identify: is called, records should go straight to main queue")
            mixpanel.track(event: "e2")
            waitForSerialQueue()
            let newDistinctId = mixpanel.eventsQueue.last?["properties"]?["distinct_id"]
            XCTAssertEqual(newDistinctId, distinctId,
                           "events should use new distinct id after identify:")
            mixpanel.reset()
            waitForSerialQueue()
        }
    }
    func testTrackWithDefaultProperties() {
        mixpanel.track(event: "Something Happened")
        waitForSerialQueue()
        var e: Properties = mixpanel.eventsQueue.last!
        XCTAssertEqual(e["event"] as? String, "Something Happened", "incorrect event name")
        var p: Properties = e["properties"] as! [String: AnyObject]
        XCTAssertNotNil(p["$app_version"], "$app_version not set")
        XCTAssertNotNil(p["$app_release"], "$app_release not set")
        XCTAssertNotNil(p["$lib_version"], "$lib_version not set")
        XCTAssertNotNil(p["$model"], "$model not set")
        XCTAssertNotNil(p["$os"], "$os not set")
        XCTAssertNotNil(p["$os_version"], "$os_version not set")
        XCTAssertNotNil(p["$screen_height"], "$screen_height not set")
        XCTAssertNotNil(p["$screen_width"], "$screen_width not set")
        XCTAssertNotNil(p["distinct_id"], "distinct_id not set")
        XCTAssertNotNil(p["mp_device_model"], "mp_device_model not set")
        XCTAssertNotNil(p["time"], "time not set")
        XCTAssertEqual(p["$manufacturer"] as? String, "Apple", "incorrect $manufacturer")
        XCTAssertEqual(p["mp_lib"] as? String, "iphone", "incorrect mp_lib")
        XCTAssertEqual(p["token"] as? String, kTestToken, "incorrect token")
    }

    func testTrackWithCustomProperties() {
        let now = Date()
        let p: Properties = ["string": "yello",
                             "number": 3,
                             "date": now,
                             "$app_version": "override"]
        mixpanel.track(event: "Something Happened", properties: p)
        waitForSerialQueue()
        var props: Properties = mixpanel.eventsQueue.last?["properties"] as! Properties
        XCTAssertEqual(props["string"] as? String, "yello")
        XCTAssertEqual(props["number"] as? Int, 3)
        XCTAssertEqual(props["date"] as? Date, now)
        XCTAssertEqual(props["$app_version"] as? String, "override",
                       "reserved property override failed")
    }

    func testTrackWithCustomDistinctIdAndToken() {
        let p: Properties = ["token": "t1", "distinct_id": "d1"]
        mixpanel.track(event: "e1", properties: p)
        waitForSerialQueue()
        let trackToken = mixpanel.eventsQueue.last?["properties"]?["token"]!
        let trackDistinctId = mixpanel.eventsQueue.last?["properties"]?["distinct_id"]!
        XCTAssertEqual(trackToken, "t1", "user-defined distinct id not used in track.")
        XCTAssertEqual(trackDistinctId, "d1", "user-defined distinct id not used in track.")
    }

    func testRegisterSuperProperties() {
        var p: Properties = ["p1": "a", "p2": 3, "p3": Date()]
        mixpanel.registerSuperProperties(p)
        waitForSerialQueue()
        XCTAssertEqual(NSDictionary(dictionary: mixpanel.currentSuperProperties()),
                       NSDictionary(dictionary: p),
                       "register super properties failed")
        p = ["p1": "b"]
        mixpanel.registerSuperProperties(p)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.currentSuperProperties()["p1"] as? String, "b",
                       "register super properties failed to overwrite existing value")
        p = ["p4": "a"]
        mixpanel.registerSuperPropertiesOnce(p)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.currentSuperProperties()["p4"] as? String, "a",
                       "register super properties once failed first time")
        p = ["p4": "b"]
        mixpanel.registerSuperPropertiesOnce(p)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.currentSuperProperties()["p4"] as? String, "a",
                       "register super properties once failed second time")
        p = ["p4": "c"]
        mixpanel.registerSuperPropertiesOnce(p, defaultValue: "d")
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.currentSuperProperties()["p4"] as? String, "a",
                       "register super properties once with default value failed when no match")
        mixpanel.registerSuperPropertiesOnce(p, defaultValue: "a")
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.currentSuperProperties()["p4"] as? String, "c",
                       "register super properties once with default value failed when match")
        mixpanel.unregisterSuperProperty("a")
        waitForSerialQueue()
        XCTAssertNil(mixpanel.currentSuperProperties()["a"],
                     "unregister super property failed")
        // unregister non-existent super property should not throw
        mixpanel.unregisterSuperProperty("a")
        mixpanel.clearSuperProperties()
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "clear super properties failed")
    }

    func testInvalidPropertiesTrack() {
        let p: Properties = ["data": Data()]
        XCTExpectAssert("property type should not be allowed") {
            mixpanel.track(event: "e1", properties: p)
        }
    }

    func testInvalidSuperProperties() {
        let p: Properties = ["data": Data()]
        XCTExpectAssert("property type should not be allowed") {
            mixpanel.registerSuperProperties(p)
        }
        XCTExpectAssert("property type should not be allowed") {
            mixpanel.registerSuperPropertiesOnce(p)
        }
        XCTExpectAssert("property type should not be allowed") {
            mixpanel.registerSuperPropertiesOnce(p, defaultValue: "v")
        }
    }

    func testValidPropertiesTrack() {
        let p: Properties = allPropertyTypes()
        mixpanel.track(event: "e1", properties: p)
    }

    func testValidSuperProperties() {
        let p: Properties = allPropertyTypes()
        mixpanel.registerSuperProperties(p)
        mixpanel.registerSuperPropertiesOnce(p)
        mixpanel.registerSuperPropertiesOnce(p, defaultValue: "v")
    }

    func testTrackLaunchOptions() {
        let launchOptions: Properties = [UIApplicationLaunchOptionsRemoteNotificationKey: ["mp":
            ["m": "the_message_id", "c": "the_campaign_id"]]]
        mixpanel = Mixpanel.initialize(token: kTestToken,
                                       launchOptions: launchOptions,
                                       flushInterval: 60)
        waitForSerialQueue()
        var e: Properties = mixpanel.eventsQueue.last!
        XCTAssertEqual(e["event"] as? String, "$app_open", "incorrect event name")
        var p: Properties = e["properties"] as! Properties
        XCTAssertEqual(p["campaign_id"] as? String, "the_campaign_id", "campaign_id not equal")
        XCTAssertEqual(p["message_id"] as? String, "the_message_id", "message_id not equal")
        XCTAssertEqual(p["message_type"] as? String, "push", "type does not equal inapp")
    }

    func testTrackPushNotification() {
        mixpanel.trackPushNotification(["mp": ["m": "the_message_id", "c": "the_campaign_id"]])
        waitForSerialQueue()
        var e: Properties = mixpanel.eventsQueue.last!
        XCTAssertEqual(e["event"] as? String, "$campaign_received", "incorrect event name")
        var p: Properties = e["properties"] as! Properties
        XCTAssertEqual(p["campaign_id"] as? String, "the_campaign_id", "campaign_id not equal")
        XCTAssertEqual(p["message_id"] as? String, "the_message_id", "message_id not equal")
        XCTAssertEqual(p["message_type"] as? String, "push", "type does not equal inapp")
    }

    func testTrackPushNotificationMalformed() {
        mixpanel.trackPushNotification(["mp":
            ["m": "the_message_id", "cid": "the_campaign_id"]])
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
        mixpanel.trackPushNotification(["mp": 1])
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
        mixpanel.trackPushNotification(nil)
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
        mixpanel.trackPushNotification([:])
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
        mixpanel.trackPushNotification(["mp": "bad value"])
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "Invalid push notification was incorrectly queued.")
    }

    func testReset() {
        mixpanel.identify(distinctId: "d1")
        mixpanel.track(event: "e1")
        let p: Properties = ["p1": "a"]
        mixpanel.registerSuperProperties(p)
        mixpanel.people.set(properties: p)
        mixpanel.archive()
        mixpanel.reset()
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.distinctId,
                       mixpanel.defaultDistinctId(),
                       "distinct id failed to reset")
        XCTAssertNil(mixpanel.people.distinctId, "people distinct id failed to reset")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "super properties failed to reset")
        XCTAssertTrue(mixpanel.eventsQueue.count == 0, "events queue failed to reset")
        XCTAssertTrue(mixpanel.peopleQueue.count == 0, "people queue failed to reset")
        mixpanel = Mixpanel.initialize(token: kTestToken, launchOptions: nil, flushInterval: 60)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.distinctId, mixpanel.defaultDistinctId(),
                       "distinct id failed to reset after archive")
        XCTAssertNil(mixpanel.people.distinctId,
                     "people distinct id failed to reset after archive")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "super properties failed to reset after archive")
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "events queue failed to reset after archive")
        XCTAssertTrue(mixpanel.peopleQueue.count == 0,
                      "people queue failed to reset after archive")
    }

    func testArchive() {
        mixpanel.archive()
        mixpanel = Mixpanel.initialize(token: kTestToken, launchOptions: nil, flushInterval: 60)
        XCTAssertEqual(mixpanel.distinctId, mixpanel.defaultDistinctId(),
                       "default distinct id archive failed")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "default super properties archive failed")
        XCTAssertTrue(mixpanel.eventsQueue.count == 0, "default events queue archive failed")
        XCTAssertNil(mixpanel.people.distinctId, "default people distinct id archive failed")
        XCTAssertTrue(mixpanel.peopleQueue.count == 0, "default people queue archive failed")
        let p: Properties = ["p1": "a"]
        mixpanel.identify(distinctId: "d1")
        mixpanel.registerSuperProperties(p)
        mixpanel.track(event: "e1")
        mixpanel.people.set(properties: p)
        mixpanel.timedEvents["e2"] = 5.0
        waitForSerialQueue()
        mixpanel.archive()
        mixpanel = Mixpanel.initialize(token: kTestToken, launchOptions: nil, flushInterval: 60)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.distinctId, "d1", "custom distinct archive failed")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 1,
                      "custom super properties archive failed")
        XCTAssertEqual(mixpanel.eventsQueue.last?["event"] as? String, "e1",
                       "event was not successfully archived/unarchived")
        XCTAssertEqual(mixpanel.people.distinctId, "d1",
                       "custom people distinct id archive failed")
        XCTAssertTrue(mixpanel.peopleQueue.count == 1, "pending people queue archive failed")
        XCTAssertEqual(mixpanel.timedEvents["e2"] as? Double, 5.0,
                       "timedEvents archive failed")
        let fileManager = FileManager.default()
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.Events)!),
                      "events archive file not removed")
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.People)!),
                      "people archive file not removed")
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.Properties)!),
                      "properties archive file not removed")
        mixpanel = Mixpanel.initialize(token: kTestToken, launchOptions: nil, flushInterval: 60)
        XCTAssertEqual(mixpanel.distinctId, "d1", "expecting d1 as distinct id as initialised")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 1,
                      "default super properties expected to have 1 item")
        XCTAssertNotNil(mixpanel.eventsQueue, "default events queue from no file is nil")
        XCTAssertTrue(mixpanel.eventsQueue.count == 1, "default events queue expecting 1 item")
        XCTAssertNotNil(mixpanel.people.distinctId,
                        "default people distinct id from no file failed")
        XCTAssertNotNil(mixpanel.peopleQueue, "default people queue from no file is nil")
        XCTAssertTrue(mixpanel.peopleQueue.count == 1, "default people queue expecting 1 item")
        XCTAssertTrue(mixpanel.timedEvents.count == 1, "timedEvents expecting 1 item")
        // corrupt file
        let garbage = "garbage".data(using: String.Encoding.utf8)!
        do {
            try garbage.write(to: URL(
                fileURLWithPath: mixpanel.persistence.filePathWithType(.Events)!),
                              options: [])
            try garbage.write(to: URL(
                fileURLWithPath: mixpanel.persistence.filePathWithType(.People)!),
                              options: [])
            try garbage.write(to: URL(
                fileURLWithPath: mixpanel.persistence.filePathWithType(.Properties)!),
                              options: [])
        } catch {
            print("couldn't write data")
        }
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.Events)!),
                      "events archive file not removed")
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.People)!),
                      "people archive file not removed")
        XCTAssertTrue(fileManager.fileExists(
            atPath: mixpanel.persistence.filePathWithType(.Properties)!),
                      "properties archive file not removed")
        mixpanel = Mixpanel.initialize(token: kTestToken, launchOptions: nil, flushInterval: 60)
        waitForSerialQueue()
        XCTAssertEqual(mixpanel.distinctId, mixpanel.defaultDistinctId(),
                       "default distinct id from garbage failed")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "default super properties from garbage failed")
        XCTAssertNotNil(mixpanel.eventsQueue, "default events queue from garbage is nil")
        XCTAssertTrue(mixpanel.eventsQueue.count == 0,
                      "default events queue from garbage not empty")
        XCTAssertNil(mixpanel.people.distinctId,
                     "default people distinct id from garbage failed")
        XCTAssertNotNil(mixpanel.peopleQueue,
                        "default people queue from garbage is nil")
        XCTAssertTrue(mixpanel.peopleQueue.count == 0,
                      "default people queue from garbage not empty")
        XCTAssertTrue(mixpanel.timedEvents.count == 0,
                      "timedEvents is not empty")
    }

    func testMixpanelDelegate() {
        mixpanel.delegate = self
        mixpanel.identify(distinctId: "d1")
        mixpanel.track(event: "e1")
        mixpanel.people.set(property: "p1", to: "a")
        mixpanel.flush()
        waitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 1, "delegate should have stopped flush")
        XCTAssertTrue(mixpanel.peopleQueue.count == 1, "delegate should have stopped flush")
    }

    func testNilArguments() {
        let originalDistinctID: String = mixpanel.distinctId!
        mixpanel.identify(distinctId: nil)
        XCTAssertEqual(mixpanel.distinctId, originalDistinctID,
                       "identify nil should do nothing.")
        mixpanel.track(event: nil)
        mixpanel.track(event: nil, properties: nil)
        mixpanel.registerSuperProperties(nil)
        mixpanel.registerSuperPropertiesOnce(nil)
        mixpanel.registerSuperPropertiesOnce(nil, defaultValue: nil)
        waitForSerialQueue()
        // legacy behavior
        XCTAssertTrue(mixpanel.eventsQueue.count == 2,
                      "track with nil should create mp_event event")
        XCTAssertEqual(mixpanel.eventsQueue.last?["event"] as? String,
                       "mp_event", "track with nil should create mp_event event")
        XCTAssertNotNil(mixpanel.currentSuperProperties(),
                        "setting super properties to nil should have no effect")
        XCTAssertTrue(mixpanel.currentSuperProperties().count == 0,
                      "setting super properties to nil should have no effect")
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.set(properties: nil)
        }
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.set(property: nil, to: "a")
        }
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.set(property: "p1", to: nil)
        }
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.increment(properties: nil)
        }
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.increment(property: nil, by: 3)
        }
        XCTExpectAssert("should not take nil argument") {
            mixpanel.people.increment(property: "p1", by: nil)
        }
    }

    func testEventTiming() {
        mixpanel.track(event: "Something Happened")
        waitForSerialQueue()
        var e: Properties = mixpanel.eventsQueue.last!
        var p = e["properties"] as! Properties
        XCTAssertNil(p["$duration"], "New events should not be timed.")
        mixpanel.time(event: "400 Meters")
        mixpanel.track(event: "500 Meters")
        waitForSerialQueue()
        e = mixpanel.eventsQueue.last!
        p = e["properties"] as! Properties
        XCTAssertNil(p["$duration"], "The exact same event name is required for timing.")
        mixpanel.track(event: "400 Meters")
        waitForSerialQueue()
        e = mixpanel.eventsQueue.last!
        p = e["properties"] as! Properties
        XCTAssertNotNil(p["$duration"], "This event should be timed.")
        mixpanel.track(event: "400 Meters")
        waitForSerialQueue()
        e = mixpanel.eventsQueue.last!
        p = e["properties"] as! Properties
        XCTAssertNil(p["$duration"],
                     "Tracking the same event should require a second call to timeEvent.")
    }

    func testNetworkingWithStress() {
        _ = stubTrack().andReturn(503)
        for _ in 0..<500 {
            mixpanel.track(event: "Track Call")
        }
        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 500, "none supposed to be flushed")
        LSNocilla.sharedInstance().clearStubs()
        _ = stubTrack().andReturn(200)
        mixpanel.flushInstance.networkRequestsAllowedAfterTime = 0
        flushAndWaitForSerialQueue()
        XCTAssertTrue(mixpanel.eventsQueue.count == 0, "supposed to all be flushed")
    }

    func testTelephonyInfoInitialized() {
        XCTAssertNotNil(mixpanel.telephonyInfo, "telephonyInfo wasn't initialized")
    }
}

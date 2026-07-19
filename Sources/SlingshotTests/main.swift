// Dependency-free test runner for SlingshotCore. Runs everywhere the
// toolchain does, no Xcode required: swift run SlingshotTests
import CoreGraphics
import Foundation
import SlingshotCore

var failures = 0

func expect(_ condition: Bool, _ name: String, _ message: String) {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name): \(message)")
    }
}

let still = CGPoint(x: 0.5, y: 0.5)

func feed(_ engine: GestureEngine, _ pose: HandPose, times: Int, wrist: CGPoint? = nil) {
    for _ in 0..<times {
        engine.update(pose: pose, wrist: wrist ?? still)
    }
}

func quietEngine() -> GestureEngine {
    let engine = GestureEngine()
    engine.debugLogging = false
    return engine
}

// Arms after a steady palm
do {
    let engine = quietEngine()
    var armed = false
    engine.onArmed = { armed = true }
    feed(engine, .open, times: 30)
    expect(armed, "armsAfterSteadyPalm", "30 steady open frames should arm")
}

// Grabs after an armed fist
do {
    let engine = quietEngine()
    var grabbed = false
    engine.onGrab = { grabbed = true }
    feed(engine, .open, times: 30)
    feed(engine, .fist, times: 15)
    expect(grabbed, "grabAfterArmedFist", "1 second of steady fist after arming should grab")
}

// A waving hand never arms
do {
    let engine = quietEngine()
    var armed = false
    engine.onArmed = { armed = true }
    for i in 0..<60 {
        engine.update(pose: .open, wrist: CGPoint(x: i % 2 == 0 ? 0.2 : 0.8, y: 0.5))
    }
    expect(!armed, "movingWristNeverArms", "a waving hand must not arm")
}

// Dropped frames within grace do not reset arming
do {
    let engine = quietEngine()
    var armed = false
    engine.onArmed = { armed = true }
    feed(engine, .open, times: 20)
    feed(engine, .unknown, times: 3)
    feed(engine, .open, times: 10)
    expect(armed, "graceSurvivesDroppedFrames", "a few dropped frames must not punish an honest palm")
}

// Suppression feedback when grabbing is paused
do {
    let engine = quietEngine()
    engine.grabAllowed = { false }
    var suppressed = false
    var armed = false
    engine.onGrabSuppressed = { suppressed = true }
    engine.onArmed = { armed = true }
    feed(engine, .open, times: 20)
    expect(suppressed, "suppressionFeedback", "a steady palm while paused should surface feedback")
    expect(!armed, "suppressionBlocksArming", "grabbing must stay disabled while paused")
}

// Release requires a pending hold
do {
    let engine = quietEngine()
    engine.grabAllowed = { false }
    engine.releaseAllowed = { false }
    var released = false
    engine.onRelease = { released = true }
    feed(engine, .fist, times: 15)
    feed(engine, .open, times: 8)
    expect(!released, "releaseRequiresAllowed", "release must not fire when no hold is pending")
}

// The catch sequence primes then fires
do {
    let engine = quietEngine()
    engine.grabAllowed = { false }
    engine.releaseAllowed = { true }
    var primed = false
    var released = false
    engine.onReleasePrimed = { primed = true }
    engine.onRelease = { released = true }
    feed(engine, .fist, times: 15)
    expect(primed, "releasePrimes", "1 second of fist should prime the release")
    feed(engine, .open, times: 8)
    expect(released, "releaseFires", "opening the hand after the primed fist should release")
}

if failures > 0 {
    print("\(failures) failure(s)")
    exit(1)
}
print("All tests passed")

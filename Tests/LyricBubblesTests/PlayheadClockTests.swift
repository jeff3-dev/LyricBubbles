import Foundation
import Testing
@testable import LyricBubbles

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

@Test func clockFollowsSteadyReadings() {
    var c = PlayheadClock()
    c.ingest(position: 10, at: at(0), playing: true, forceJump: true)
    for i in 1...5 { c.ingest(position: 10 + Double(i), at: at(Double(i)), playing: true) }
    #expect(abs(c.position(at: at(5.5)) - 15.5) < 0.01)
}

@Test func clockIgnoresOneBadReading() {
    var c = PlayheadClock()
    c.ingest(position: 10, at: at(0), playing: true, forceJump: true)
    c.ingest(position: 11, at: at(1), playing: true)
    let doubtful = c.ingest(position: 20, at: at(2), playing: true)   // glitch
    #expect(doubtful)
    #expect(abs(c.position(at: at(2)) - 12) < 0.01)
    c.ingest(position: 12.15, at: at(2.15), playing: true)          // re-read disagrees with the glitch
    #expect(abs(c.position(at: at(2.15)) - 12.15) < 0.02)
}

@Test func clockJumpsOnConfirmedSeek() {
    var c = PlayheadClock()
    c.ingest(position: 10, at: at(0), playing: true, forceJump: true)
    let first = c.ingest(position: 60, at: at(1), playing: true)
    let second = c.ingest(position: 60.15, at: at(1.15), playing: true)
    #expect(first)
    #expect(!second)
    #expect(abs(c.position(at: at(1.15)) - 60.15) < 0.001)
}

@Test func clockCorrectsSmallDriftSmoothly() {
    var c = PlayheadClock()
    c.ingest(position: 10, at: at(0), playing: true, forceJump: true)
    // Spotify consistently 0.2 s ahead of our clock: closed within a few polls, without jumping.
    var last = c.position(at: at(0))
    for i in 1...6 {
        let before = c.position(at: at(Double(i)))
        c.ingest(position: 10.2 + Double(i), at: at(Double(i)), playing: true)
        #expect(abs(c.position(at: at(Double(i))) - before) < 0.001)   // continuous
        last = c.position(at: at(Double(i)))
    }
    #expect(abs(last - 16.2) < 0.05)
}

@Test func clockHoldsWhilePaused() {
    var c = PlayheadClock()
    c.ingest(position: 42, at: at(0), playing: false)
    #expect(c.position(at: at(10)) == 42)
}

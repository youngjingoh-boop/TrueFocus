import XCTest
@testable import TrueFocusKit

final class RestPolicyTests: XCTestCase {
    func testRestScalesWithFocusLength() {
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 5 * 60), 20)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 20 * 60), 45)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 40 * 60), 70)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 60 * 60), 115)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 120 * 60), 180)
    }

    func testRestIsClampedAndFixedWhenNotAdaptive() {
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 1, base: 1), 10)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 999 * 60, base: 600), 300)
        XCTAssertEqual(RestPolicy.plannedRest(afterFocus: 120 * 60, base: 30, adaptive: false), 30)
    }
}

final class DayStatsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testChainGrowsWhenRestsAreShort() {
        let a = UUID(), b = UUID(), c = UUID()
        let segments = [
            SegmentRecord(mode: .focus, taskID: a, start: at(0), end: at(20), outcome: .completed),
            SegmentRecord(mode: .rest, start: at(20), end: at(20.75), outcome: .resumed, plannedSeconds: 45),
            SegmentRecord(mode: .focus, taskID: b, start: at(20.75), end: at(50), outcome: .completed),
            SegmentRecord(mode: .rest, start: at(50), end: at(51), outcome: .resumed, plannedSeconds: 70),
            SegmentRecord(mode: .focus, taskID: c, start: at(51), end: nil),
        ]
        let stats = DayStats.compute(segments: segments, now: at(60))
        XCTAssertEqual(stats.completed, 2)
        XCTAssertEqual(stats.chain, 2)
        XCTAssertEqual(stats.bestChain, 2)
        XCTAssertEqual(stats.focusSeconds, (20 + 29.25 + 9) * 60, accuracy: 0.001)
        XCTAssertGreaterThan(stats.momentum, 25)
    }

    func testLongRestBreaksChainAndLeaksMomentum() {
        let a = UUID(), b = UUID()
        let short = [
            SegmentRecord(mode: .focus, taskID: a, start: at(0), end: at(20), outcome: .completed),
            SegmentRecord(mode: .rest, start: at(20), end: at(21), outcome: .resumed, plannedSeconds: 45),
            SegmentRecord(mode: .focus, taskID: b, start: at(21), end: at(40), outcome: .completed),
        ]
        let long = [
            SegmentRecord(mode: .focus, taskID: a, start: at(0), end: at(20), outcome: .completed),
            SegmentRecord(mode: .rest, start: at(20), end: at(35), outcome: .resumed, plannedSeconds: 45),
            SegmentRecord(mode: .focus, taskID: b, start: at(35), end: at(54), outcome: .completed),
        ]
        let good = DayStats.compute(segments: short, now: at(41))
        let bad = DayStats.compute(segments: long, now: at(55))
        XCTAssertEqual(good.chain, 2)
        XCTAssertEqual(bad.chain, 1, "the overrun rest should reset the chain before the second completion")
        XCTAssertEqual(bad.bestChain, 1)
        XCTAssertGreaterThan(bad.restOverrunSeconds, 13 * 60)
        XCTAssertLessThan(bad.momentum, good.momentum)
    }

    func testChainDiesLiveWhileStillResting() {
        let a = UUID()
        let segments = [
            SegmentRecord(mode: .focus, taskID: a, start: at(0), end: at(20), outcome: .completed),
            SegmentRecord(mode: .rest, start: at(20), end: nil, plannedSeconds: 45),
        ]
        XCTAssertEqual(DayStats.compute(segments: segments, now: at(21)).chain, 1)
        XCTAssertEqual(DayStats.compute(segments: segments, now: at(30)).chain, 0)
    }

    func testBootsCostMomentum() {
        let segments = [SegmentRecord(mode: .focus, taskID: UUID(), start: at(0), end: at(60), outcome: .completed)]
        let clean = DayStats.compute(segments: segments, boots: 0, now: at(60))
        let booted = DayStats.compute(segments: segments, boots: 2, now: at(60))
        XCTAssertEqual(clean.momentum - booted.momentum, 16)
        XCTAssertEqual(booted.boots, 2)
    }

    func testMomentumIsBounded() {
        var segments: [SegmentRecord] = []
        for i in 0..<40 {
            let s = Double(i) * 21
            segments.append(SegmentRecord(mode: .focus, taskID: UUID(), start: at(s), end: at(s + 20), outcome: .completed))
            segments.append(SegmentRecord(mode: .rest, start: at(s + 20), end: at(s + 20.5), outcome: .resumed, plannedSeconds: 45))
        }
        let stats = DayStats.compute(segments: segments, now: at(40 * 21))
        XCTAssertLessThanOrEqual(stats.momentum, 100)
        XCTAssertGreaterThan(stats.momentum, 90)
        XCTAssertEqual(stats.bestChain, 40)
    }

    func testEmptyDay() {
        let stats = DayStats.compute(segments: [], now: t0)
        XCTAssertEqual(stats, DayStats())
    }
}

final class NudgePlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func testRestNudgesEscalateAfterPlannedEnd() {
        let end = now.addingTimeInterval(45)
        let nudges = NudgePlanner.plan(NudgeContext(mode: .rest, modeStartedAt: now, plannedRestEnd: end,
                                                    nextTaskTitle: "Send investor update", openTaskCount: 3,
                                                    tone: .savage, now: now))
        XCTAssertEqual(nudges.first?.fireAt, end.addingTimeInterval(RestPolicy.grace))
        XCTAssertEqual(nudges.map(\.level), [1, 2, 3, 3, 3])
        XCTAssertTrue(nudges.last!.title.contains("Wake the fuck up"))
        XCTAssertTrue(nudges[1].body.contains("Send investor update"))
    }

    func testPastNudgesAreDropped() {
        let start = now.addingTimeInterval(-10 * 60)
        let nudges = NudgePlanner.plan(NudgeContext(mode: .rest, modeStartedAt: start,
                                                    plannedRestEnd: start.addingTimeInterval(45), now: now))
        XCTAssertEqual(nudges.map(\.id), ["rest.3", "rest.4"])
    }

    func testIdleNudgesNeedOpenTasks() {
        XCTAssertTrue(NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: now, openTaskCount: 0, now: now)).isEmpty)
        XCTAssertEqual(NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: now, openTaskCount: 2, now: now)).count, 4)
    }

    func testNoNudgesAfterShutdown() {
        XCTAssertTrue(NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: now, openTaskCount: 5,
                                                     dayEnded: true, now: now)).isEmpty)
    }

    func testThinkNudgesUseSetting() {
        let nudges = NudgePlanner.plan(NudgeContext(mode: .think, modeStartedAt: now, taskTitle: "Pricing page",
                                                    thinkNudgeMinutes: 3, now: now))
        XCTAssertEqual(nudges.map { $0.fireAt.timeIntervalSince(now) }, [180, 360, 720])
    }

    func testEveryToneHasCopyForEveryLevel() {
        for tone in NudgeTone.allCases {
            let copy = Copy(tone: tone)
            for level in 1...3 {
                XCTAssertFalse(copy.restOver(level: level, next: nil).title.isEmpty)
                XCTAssertFalse(copy.stuck(level: level, task: "x").body.isEmpty)
                XCTAssertFalse(copy.idle(level: level, next: "x", left: 1).body.isEmpty)
            }
            XCTAssertTrue(copy.bootOut(site: "Instagram", task: "Deck").body.contains("Deck"))
        }
    }
}

final class DoomScrollTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 3_000_000)

    func testSlowReadingIsCalm() {
        var detector = DoomScrollDetector()
        var verdict = DoomScrollDetector.Verdict.calm
        // One stroke every 12 seconds for two minutes: reading an article.
        for i in 0..<10 { verdict = detector.stroke(at: t0.addingTimeInterval(Double(i) * 12)) }
        XCTAssertEqual(verdict, .calm)
    }

    func testFastSkimmingBootsOnBurst() {
        var detector = DoomScrollDetector()
        var verdict = DoomScrollDetector.Verdict.calm
        for i in 0..<25 { verdict = detector.stroke(at: t0.addingTimeInterval(Double(i) * 2)) }
        XCTAssertEqual(verdict, .boot(.burst))
    }

    func testWarnsBeforeBooting() {
        var detector = DoomScrollDetector()
        var sawWarn = false
        for i in 0..<25 {
            if case .warn = detector.stroke(at: t0.addingTimeInterval(Double(i) * 2)) { sawWarn = true }
        }
        XCTAssertTrue(sawWarn)
    }

    func testReelsSwipingBootsOnBinge() {
        var detector = DoomScrollDetector()
        var verdict = DoomScrollDetector.Verdict.calm
        // One swipe every 8 seconds never trips the burst rule, but 60 of them is a binge.
        var i = 0
        while i < 80 {
            verdict = detector.stroke(at: t0.addingTimeInterval(Double(i) * 8))
            if case .boot = verdict { break }
            i += 1
        }
        XCTAssertEqual(verdict, .boot(.binge))
        XCTAssertEqual(i, 59)
    }

    func testPauseResetsTheSitting() {
        // Dwell is deliberately cumulative across sittings; isolate the binge rule.
        var detector = DoomScrollDetector(config: DoomScrollConfig(dwellSeconds: 3600))
        for i in 0..<40 { detector.stroke(at: t0.addingTimeInterval(Double(i) * 8)) }
        // A two-minute pause ends the sitting.
        let resume = t0.addingTimeInterval(40 * 8 + 120)
        var verdict = DoomScrollDetector.Verdict.calm
        for i in 0..<30 { verdict = detector.stroke(at: resume.addingTimeInterval(Double(i) * 8)) }
        if case .boot = verdict { XCTFail("sitting should have reset after the pause") }
    }

    func testDwellBootsEvenAtAGentlePace() {
        var detector = DoomScrollDetector(config: DoomScrollConfig(sessionStrokes: 1000, dwellSeconds: 300))
        var verdict = DoomScrollDetector.Verdict.calm
        var t = t0
        for _ in 0..<40 {
            verdict = detector.stroke(at: t)
            t.addTimeInterval(10)
            verdict = detector.tick(at: t)
            if case .boot = verdict { break }
        }
        XCTAssertEqual(verdict, .boot(.dwell))
        XCTAssertGreaterThanOrEqual(detector.engagedTime, 300)
    }

    func testStrictModeDuringFocusIsMuchFaster() {
        var detector = DoomScrollDetector(strict: true)
        var count = 0
        for i in 0..<30 {
            count = i + 1
            if case .boot = detector.stroke(at: t0.addingTimeInterval(Double(i) * 3)) { break }
        }
        XCTAssertEqual(count, 8)
    }

    func testIdleTimeDoesNotCountAsDwell() {
        var detector = DoomScrollDetector()
        detector.stroke(at: t0)
        detector.tick(at: t0.addingTimeInterval(3600))
        XCTAssertEqual(detector.engagedTime, 45, accuracy: 0.001)
    }

    func testConfigDecodesWithMissingKeys() throws {
        let config = try JSONDecoder().decode(DoomScrollConfig.self, from: Data(#"{"burstStrokes": 10}"#.utf8))
        XCTAssertEqual(config.burstStrokes, 10)
        XCTAssertEqual(config.sessionStrokes, DoomScrollConfig.standard.sessionStrokes)
    }
}

final class NoteDocumentTests: XCTestCase {
    func testRoundTrip() {
        let markup = """
        Launch plan
        ## Today
        Ideas for the landing page
        - bullet
        - [ ] Write hero copy
        - [x] Pick a domain
        - [ ]
        """
        let doc = NoteDocument(markup: markup)
        XCTAssertEqual(doc.lines.count, 7)
        XCTAssertEqual(doc.lines[0], NoteLine(.title, "Launch plan"))
        XCTAssertEqual(doc.lines[1], NoteLine(.heading, "Today"))
        XCTAssertEqual(doc.lines[4], NoteLine(.checklist(done: false), "Write hero copy"))
        XCTAssertEqual(doc.lines[5], NoteLine(.checklist(done: true), "Pick a domain"))
        XCTAssertEqual(doc.lines[6], NoteLine(.checklist(done: false), ""))
        XCTAssertEqual(doc.markup, markup)
        XCTAssertEqual(doc.openChecklistItems, ["Write hero copy"])
        XCTAssertEqual(doc.checklistProgress.done, 1)
        XCTAssertEqual(doc.checklistProgress.total, 3)
        XCTAssertEqual(doc.preview, "Today")
    }

    func testToggle() {
        var doc = NoteDocument(markup: "T\n- [ ] a")
        doc.toggleChecklist(at: 1)
        XCTAssertEqual(doc.markup, "T\n- [x] a")
        doc.toggleChecklist(at: 0)
        XCTAssertEqual(doc.markup, "T\n- [x] a")
    }

    func testEmptyAndUntitled() {
        XCTAssertEqual(NoteDocument(markup: "").title, "New Note")
        XCTAssertEqual(NoteDocument(markup: "\nsecond").title, "second")
        XCTAssertEqual(NoteDocument(markup: "# Hello").title, "Hello")
    }
}

final class BrainDumpTests: XCTestCase {
    func testStripsMarkersAndDedupes() {
        let text = """
        Work:
        - email investors
        * fix login bug
        1. Call the designer
        2) call the designer
        - [x] already done
        • Draft pricing page
        [ ] book flights

        """
        XCTAssertEqual(BrainDump.extractTasks(from: text),
                       ["Email investors", "Fix login bug", "Call the designer", "Draft pricing page", "Book flights"])
    }

    func testCommaSeparatedSingleLine() {
        XCTAssertEqual(BrainDump.extractTasks(from: "gym, reply to Sam, ship v2"), ["Gym", "Reply to Sam", "Ship v2"])
        XCTAssertEqual(BrainDump.extractTasks(from: "Finish the deck, then sleep"), ["Finish the deck, then sleep"])
    }

    func testLongLinesAreTruncated() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(BrainDump.extractTasks(from: long).first?.count, 140)
    }
}

final class BlocklistTests: XCTestCase {
    func testAdultHosts() {
        XCTAssertTrue(Blocklist.isAdult(host: "www.pornhub.com"))
        XCTAssertTrue(Blocklist.isAdult(host: "de.xhamster.com"))
        XCTAssertTrue(Blocklist.isAdult(host: "some-random-porn-site.net"))
        XCTAssertFalse(Blocklist.isAdult(host: "github.com"))
        XCTAssertFalse(Blocklist.isAdult(host: "essex.ac.uk"))
    }

    func testFeedSitesAndShortForm() throws {
        let ig = try XCTUnwrap(Blocklist.feedSite(forHost: "www.instagram.com"))
        XCTAssertTrue(ig.isShortForm(path: "/reels/"))
        XCTAssertTrue(ig.isShortForm(path: "/reel/C1abc/"))
        XCTAssertTrue(ig.isShortForm(path: "/explore/"))
        XCTAssertFalse(ig.isShortForm(path: "/reelsmith/"))
        XCTAssertFalse(ig.isShortForm(path: "/direct/inbox/"))
        XCTAssertTrue(ig.isSafe(path: "/direct/t/123"))
        XCTAssertEqual(ig.respondPath, "/direct/inbox/")

        let yt = try XCTUnwrap(Blocklist.feedSite(forHost: "m.youtube.com"))
        XCTAssertTrue(yt.isShortForm(path: "/shorts/abc"))
        XCTAssertFalse(yt.isShortForm(path: "/watch"))

        let tt = try XCTUnwrap(Blocklist.feedSite(forHost: "www.tiktok.com"))
        XCTAssertTrue(tt.isShortForm(path: "/@someone/video/1"))
        XCTAssertFalse(tt.isShortForm(path: "/messages"))

        XCTAssertNil(Blocklist.feedSite(forHost: "notion.so"))
    }

    func testAdultDomainsAreUniqueAndLowercase() {
        XCTAssertEqual(Set(Blocklist.adultDomains).count, Blocklist.adultDomains.count)
        XCTAssertTrue(Blocklist.adultDomains.allSatisfy { $0 == $0.lowercased() && !$0.hasPrefix("www.") })
    }
}

final class SharedStoreTests: XCTestCase {
    func makeStore() -> SharedStore {
        let suite = "tf.tests.\(UUID().uuidString)"
        return SharedStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func testSnapshotRoundTrip() {
        let store = makeStore()
        XCTAssertEqual(store.snapshot.mode, .idle)
        let snapshot = LiveSnapshot(mode: .focus, taskID: UUID(), taskTitle: "Ship", modeStartedAt: Date(timeIntervalSince1970: 100),
                                    inPlay: [.init(id: UUID(), title: "Ship")], doneToday: 2, plannedToday: 5,
                                    updatedAt: Date(timeIntervalSince1970: 200), originDevice: "Mac")
        store.snapshot = snapshot
        XCTAssertEqual(store.snapshot, snapshot)
    }

    func testAdultFilterCoolOff() {
        var settings = TFSettings()
        let t0 = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(settings.adultFilterActive(now: t0))
        settings.adultFilterOffRequestedAt = t0
        XCTAssertTrue(settings.adultFilterActive(now: t0.addingTimeInterval(23 * 3600)))
        XCTAssertFalse(settings.adultFilterActive(now: t0.addingTimeInterval(25 * 3600)))
        XCTAssertEqual(settings.adultFilterOffEffectiveAt, t0.addingTimeInterval(24 * 3600))
        settings.adultFilterOffRequestedAt = nil
        settings.adultFilterEnabled = false
        XCTAssertFalse(settings.adultFilterActive(now: t0))
    }

    func testSettingsAreNormalized() {
        let store = makeStore()
        var settings = TFSettings()
        settings.scrollCooldownMinutes = 2
        store.settings = settings
        XCTAssertEqual(store.settings.scrollCooldownMinutes, 15)
    }

    func testBootsAndCommandsDrain() {
        let store = makeStore()
        store.appendBoot(BootEvent(source: "web", site: "instagram.com"))
        store.enqueue(RemoteCommand(kind: .complete))
        XCTAssertEqual(store.drainBoots().count, 1)
        XCTAssertEqual(store.drainBoots().count, 0)
        XCTAssertEqual(store.drainCommands().map(\.kind), [.complete])
        XCTAssertTrue(store.drainCommands().isEmpty)
    }

    func testOldSnapshotJSONStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(LiveSnapshot.self, from: Data(#"{"mode":"rest","taskTitle":"x"}"#.utf8))
        XCTAssertEqual(snapshot.mode, .rest)
        XCTAssertEqual(snapshot.inPlay, [])
    }
}

final class FormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(TFFormat.clock(0), "0:00")
        XCTAssertEqual(TFFormat.clock(65), "1:05")
        XCTAssertEqual(TFFormat.clock(3725), "1:02:05")
        XCTAssertEqual(TFFormat.short(42), "42s")
        XCTAssertEqual(TFFormat.short(12 * 60 + 5), "12m")
        XCTAssertEqual(TFFormat.short(3900), "1h 05m")
    }

    func testEyebrow() {
        let date = Date(timeIntervalSince1970: 1_792_224_000) // 2026-10-17 UTC
        XCTAssertEqual(TFFormat.dayEyebrow(date, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!),
                       "SAT · OCT 17")
    }

    func testDayRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight: TimeInterval = 1_792_195_200 // 2026-10-17 00:00 UTC
        let oneAM = Date(timeIntervalSince1970: midnight + 3600)
        XCTAssertEqual(calendar.tfDayStart(for: oneAM), Date(timeIntervalSince1970: midnight - 20 * 3600)) // 04:00 on the 16th
        let nineAM = Date(timeIntervalSince1970: midnight + 9 * 3600)
        XCTAssertEqual(calendar.tfDayStart(for: nineAM), Date(timeIntervalSince1970: midnight + 4 * 3600))
    }

    func testTruncate() {
        XCTAssertEqual(TFFormat.truncate("Write the investor update", to: 10), "Write the…")
        XCTAssertEqual(TFFormat.truncate("Short", to: 10), "Short")
    }
}

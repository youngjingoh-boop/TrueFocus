import XCTest
@testable import TrueFocusKit

final class WorkPlatformSwitchTests: XCTestCase {
    func testOpeningAMacFeedAppOpensItsWebsite() {
        var s = TFSettings.default
        s.setOpenForWork("YouTube", true)
        XCTAssertEqual(s.macAllowedFeedApps, ["com.google.ios.youtube"])
        XCTAssertEqual(s.workPlatforms, ["YouTube"])
        s.setOpenForWork("YouTube", false)
        XCTAssertTrue(s.macAllowedFeedApps.isEmpty)
        XCTAssertTrue(s.workPlatforms.isEmpty)
    }

    func testPlatformsWithoutAWebsiteModeOnlyOpenTheApp() {
        var s = TFSettings.default
        s.setOpenForWork("Netflix", true)
        XCTAssertEqual(s.macAllowedFeedApps, ["com.netflix.Netflix"])
        XCTAssertTrue(s.workPlatforms.isEmpty)
    }

    func testFacebookOpensTheAppAndTheWholeWebsite() {
        var s = TFSettings.default
        s.setOpenForWork("Facebook", true)
        XCTAssertEqual(s.macAllowedFeedApps, ["com.facebook.Facebook"])
        XCTAssertEqual(s.workPlatforms, ["Facebook"])
        // Work-only Facebook (no posts anywhere) is untouched; it applies again once closed.
        XCTAssertTrue(s.facebookWorkOnly)
    }

    func testOlderSettingsWithOnlyTheAppOpenGetTheWebsiteToo() throws {
        var old = TFSettings.default
        old.macAllowedFeedApps = ["com.google.ios.youtube"]
        old.workPlatforms = ["X"]
        let decoded = try JSONDecoder().decode(TFSettings.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(Set(decoded.workPlatforms), ["YouTube", "X"])
        XCTAssertEqual(Set(decoded.macAllowedFeedApps), ["com.google.ios.youtube", "com.atebits.Tweetie2"])
    }
}

final class DriftTests: XCTestCase {
    let task = UUID()
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    private var marketing: TaskContract {
        TaskContract(taskID: task, taskTitle: "ScaleMaster marketing research",
                     apps: ["com.notion.id"], sites: ["claude.ai", "docs.google.com"],
                     keywords: ["마케팅", "channels"])
    }

    // MARK: Words

    func testTopicWordsKeepContentWordsInAnyScript() {
        XCTAssertEqual(TopicWords.extract("Marketing brainstorm for the new app"), ["marketing", "brainstorm"])
        XCTAssertEqual(TopicWords.extract("스케일마스터 마케팅 조사"), ["스케일마스터", "마케팅", "조사"])
        XCTAssertTrue(TopicWords.overlaps(["마케팅"], with: "마케팅을 위한 채널 정리"))
    }

    // MARK: Classifier

    func testDeclaredSitesAndAppsAreOnTask() {
        XCTAssertEqual(DriftClassifier.classify(ActivitySample(appBundleID: "com.google.Chrome", host: "claude.ai", pageTitle: "Chat"), contract: marketing), .onTask)
        XCTAssertEqual(DriftClassifier.classify(ActivitySample(appBundleID: "com.google.Chrome", host: "www.docs.google.com", pageTitle: "Plan"), contract: marketing), .onTask)
        XCTAssertEqual(DriftClassifier.classify(ActivitySample(appBundleID: "com.notion.id", appName: "Notion", windowTitle: "Inbox"), contract: marketing), .onTask)
    }

    func testTheClinicTabIsDrift() {
        // The founder's own afternoon: hunting for old marketing research, ending up on breast-surgery prices.
        let clinic = ActivitySample(appBundleID: "com.google.Chrome", host: "www.gangnam-clinic.co.kr", pageTitle: "가슴성형 비용 2026 | 강남 성형외과")
        XCTAssertEqual(DriftClassifier.classify(clinic, contract: marketing), .offTask)
        let noWorkspace = TaskContract(taskID: task, taskTitle: "ScaleMaster marketing research")
        XCTAssertEqual(DriftClassifier.classify(clinic, contract: noWorkspace), .unsure)
    }

    func testTitleWordsRescueResearchOnUndeclaredSites() {
        let search = ActivitySample(appBundleID: "com.google.Chrome", host: "www.google.com", pageTitle: "scalemaster competitors marketing - Google Search")
        XCTAssertEqual(DriftClassifier.classify(search, contract: marketing), .onTask)
        let korean = ActivitySample(appBundleID: "com.apple.Safari", host: "blog.naver.com", pageTitle: "B2B 마케팅 채널 정리")
        XCTAssertEqual(DriftClassifier.classify(korean, contract: marketing), .onTask)
    }

    func testWorkAccessMakesFeedsCountLikeAnyOtherAppOrSite() {
        let youtube = ActivitySample(appBundleID: "com.google.Chrome", host: "www.youtube.com", pageTitle: "Lo-fi beats")
        let youtubeApp = ActivitySample(appBundleID: "com.google.ios.youtube", appName: "YouTube", windowTitle: "YouTube")
        let open = TaskContract(taskID: task, taskTitle: "Teach a client")
        // Without work access a feed is drift on sight.
        XCTAssertEqual(DriftClassifier.classify(youtube, contract: open), .offTask)
        XCTAssertEqual(DriftClassifier.classify(youtubeApp, contract: open), .offTask)
        // Opened up for work, it waits for the rules (or the on-device judge) like anything else.
        XCTAssertEqual(DriftClassifier.classify(youtube, contract: open, workAccess: ["YouTube"]), .unsure)
        XCTAssertEqual(DriftClassifier.classify(youtubeApp, contract: open, workAccess: ["com.google.ios.youtube"]), .unsure)
        // A task that names its own workspace still treats it as off the task.
        XCTAssertEqual(DriftClassifier.classify(youtube, contract: marketing, workAccess: ["YouTube"]), .offTask)
    }

    func testFeedAppsYouAllowAreNotShielded() {
        let all = Blocklist.macShieldedApps(custom: ["com.example.Game"], allowedFeedApps: [])
        XCTAssertTrue(all.contains("com.google.ios.youtube"))
        XCTAssertTrue(all.contains("com.example.Game"))
        let some = Blocklist.macShieldedApps(custom: [], allowedFeedApps: ["com.google.ios.youtube", "com.burbn.instagram"])
        XCTAssertFalse(some.contains("com.google.ios.youtube"))
        XCTAssertFalse(some.contains("com.burbn.instagram"))
        XCTAssertTrue(some.contains("com.zhiliaoapp.musically"))
        var settings = TFSettings.default
        settings.workPlatforms = ["YouTube"]
        settings.macAllowedFeedApps = ["com.facebook.Facebook"]
        XCTAssertEqual(Blocklist.workAccess(settings), ["YouTube", "com.facebook.Facebook"])
    }

    func testOlderSettingsDecodeWithNothingOpenedUp() throws {
        let decoded = try JSONDecoder().decode(TFSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.workPlatforms, [])
        XCTAssertEqual(decoded.macAllowedFeedApps, [])
    }

    func testFeedsUtilitiesAndBuildingTheAppInstead() {
        XCTAssertEqual(DriftClassifier.classify(ActivitySample(appBundleID: "com.google.Chrome", host: "www.youtube.com", pageTitle: "Lo-fi beats"), contract: marketing), .offTask)
        XCTAssertEqual(DriftClassifier.classify(ActivitySample(appBundleID: "com.apple.finder", appName: "Finder"), contract: marketing), .neutral)
        let xcode = ActivitySample(appBundleID: "com.apple.dt.Xcode", appName: "Xcode", windowTitle: "TrueFocus — DriftGuard.swift")
        XCTAssertEqual(DriftClassifier.classify(xcode, contract: marketing), .offTask)
    }

    func testABrowserIsNeverOnTaskAsAWholeApp() {
        var contract = marketing
        contract.apps.append("com.google.Chrome")
        let other = ActivitySample(appBundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Flight deals to Jeju")
        XCTAssertNotEqual(DriftClassifier.classify(other, contract: contract), .onTask)
        contract.include(other)
        XCTAssertEqual(contract.apps.filter { $0 == "com.google.Chrome" }.count, 1, "browsers aren't added as whole apps")
    }

    func testABrowserWithoutATabReportIsUnsureNotDrift() {
        // No extension (or a stale report): the site is unknown, so a declared site can't be
        // recognised. This was offTask, which nudged people on their own Google Doc after 90 s.
        let doc = ActivitySample(appBundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Q4 plan - Google Docs")
        XCTAssertEqual(DriftClassifier.classify(doc, contract: marketing), .unsure)
        let feed = ActivitySample(appBundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Lo-fi beats - YouTube")
        XCTAssertEqual(DriftClassifier.classify(feed, contract: marketing), .offTask, "an obvious feed in the title still counts")
        let topical = ActivitySample(appBundleID: "com.apple.Safari", appName: "Safari", windowTitle: "B2B 마케팅 채널")
        XCTAssertEqual(DriftClassifier.classify(topical, contract: marketing), .onTask)
        let untitled = ActivitySample(appBundleID: "com.google.Chrome", appName: "Chrome", windowTitle: nil)
        XCTAssertEqual(DriftClassifier.classify(untitled, contract: marketing), .unsure)
    }

    func testMailAndChatAreUnsureCallsAreNeutral() {
        let slack = ActivitySample(appBundleID: "com.tinyspeck.slackmacgap", appName: "Slack", windowTitle: "general (Channel) - Acme")
        XCTAssertEqual(DriftClassifier.classify(slack, contract: marketing), .unsure, "a quick reply isn't drift")
        let mail = ActivitySample(appBundleID: "com.apple.mail", appName: "Mail", windowTitle: "Inbox")
        XCTAssertEqual(DriftClassifier.classify(mail, contract: marketing), .unsure)
        let kakao = ActivitySample(appBundleID: "com.kakao.KakaoTalkMac", appName: "KakaoTalk", windowTitle: nil)
        XCTAssertEqual(DriftClassifier.classify(kakao, contract: marketing), .unsure)
        let gmail = ActivitySample(appBundleID: "com.google.Chrome", host: "mail.google.com", pageTitle: "Inbox (3)")
        XCTAssertEqual(DriftClassifier.classify(gmail, contract: marketing), .unsure)
        let zoom = ActivitySample(appBundleID: "us.zoom.xos", appName: "zoom.us", windowTitle: "Zoom Meeting")
        XCTAssertEqual(DriftClassifier.classify(zoom, contract: marketing), .neutral)
        // Declared, or on topic, it's the task.
        var withSlack = marketing
        withSlack.include(slack)
        XCTAssertEqual(DriftClassifier.classify(slack, contract: withSlack), .onTask)
        let topical = ActivitySample(appBundleID: "com.apple.mail", appName: "Mail", windowTitle: "Re: ScaleMaster channels")
        XCTAssertEqual(DriftClassifier.classify(topical, contract: marketing), .onTask)
    }

    func testIncludeLearnsTheSiteOrApp() {
        var contract = marketing
        let figma = ActivitySample(appBundleID: "com.figma.Desktop", appName: "Figma", windowTitle: "Ads v2")
        XCTAssertEqual(DriftClassifier.classify(figma, contract: contract), .offTask)
        contract.include(figma)
        XCTAssertEqual(DriftClassifier.classify(figma, contract: contract), .onTask)
        let reddit = ActivitySample(appBundleID: "com.google.Chrome", host: "www.reddit.com", pageTitle: "r/ADHD")
        contract.include(reddit)
        XCTAssertTrue(contract.sites.contains("reddit.com"))
        XCTAssertEqual(DriftClassifier.classify(reddit, contract: contract), .onTask)
    }

    // MARK: Monitor

    private let clinic = ActivitySample(appBundleID: "com.google.Chrome", host: "clinic.co.kr", pageTitle: "가슴성형 비용")
    private let doc = ActivitySample(appBundleID: "com.google.Chrome", host: "docs.google.com", pageTitle: "Channels")

    func testQuickLookupsNeverNudge() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        let later = t0.addingTimeInterval(600)
        XCTAssertNil(monitor.observe(doc, verdict: .onTask, at: later))
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(5)))
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(60)))
        XCTAssertNil(monitor.observe(doc, verdict: .onTask, at: later.addingTimeInterval(70)))
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(120)))
    }

    func testSustainedDriftNudgesThenWaitsBeforeRepeating() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        let later = t0.addingTimeInterval(600)
        _ = monitor.observe(doc, verdict: .onTask, at: later)
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(10)))
        let nudge = monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(100))
        XCTAssertEqual(nudge?.label, "clinic.co.kr")
        XCTAssertEqual(nudge?.lastOnTask, doc)
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(160)), "no repeat inside the re-nudge gap")
        XCTAssertNotNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(100 + 4 * 60)))
    }

    func testWarmUpIsPatientAndIgnoresUnsure() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        XCTAssertNil(monitor.observe(clinic, verdict: .unsure, at: t0.addingTimeInterval(10)))
        XCTAssertNil(monitor.observe(clinic, verdict: .unsure, at: t0.addingTimeInterval(250)), "unsure never nudges while focus is arriving")
        var strict = DriftMonitor()
        strict.begin(taskID: task, title: "Marketing", at: t0)
        XCTAssertNil(strict.observe(clinic, verdict: .offTask, at: t0.addingTimeInterval(10)))
        XCTAssertNil(strict.observe(clinic, verdict: .offTask, at: t0.addingTimeInterval(100)), "warm-up doubles the wait")
        XCTAssertNotNil(strict.observe(clinic, verdict: .offTask, at: t0.addingTimeInterval(200)))
    }

    func testNeutralUtilitiesDoNotResetDrift() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        let later = t0.addingTimeInterval(600)
        _ = monitor.observe(clinic, verdict: .offTask, at: later)
        _ = monitor.observe(ActivitySample(appBundleID: "com.apple.finder"), verdict: .neutral, at: later.addingTimeInterval(40))
        XCTAssertNotNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(95)))
    }

    func testTallyCountsTimeAndWhereDriftWent() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        _ = monitor.observe(doc, verdict: .onTask, at: t0)
        _ = monitor.observe(clinic, verdict: .offTask, at: t0.addingTimeInterval(30))
        _ = monitor.observe(clinic, verdict: .offTask, at: t0.addingTimeInterval(60))
        _ = monitor.observe(doc, verdict: .onTask, at: t0.addingTimeInterval(90))
        // A long gap (the Mac slept) counts at most a minute.
        let tally = monitor.end(at: t0.addingTimeInterval(90 + 3600))
        XCTAssertEqual(tally?.onTask, 30 + 60)
        XCTAssertEqual(tally?.offTask, 60)
        XCTAssertEqual(tally?.topDrift?.label, "clinic.co.kr")
    }

    func testBookKeepsTodayOnly() throws {
        var book = DriftBook()
        var tally = DriftTally(taskTitle: "Marketing")
        tally.onTask = 1200
        tally.offTask = 300
        tally.drift = ["clinic.co.kr": 300]
        book.record(tally, for: task, dayKey: "2026-10-19")
        book.save(marketing)
        XCTAssertEqual(book.today(dayKey: "2026-10-19").onTask, 1200)
        XCTAssertEqual(book.today(dayKey: "2026-10-19").top?.label, "clinic.co.kr")
        XCTAssertEqual(book.today(dayKey: "2026-10-20").offTask, 0)
        let data = try JSONEncoder().encode(book)
        let back = try JSONDecoder().decode(DriftBook.self, from: data)
        XCTAssertEqual(back.contracts[task]?.sites, ["claude.ai", "docs.google.com"])
    }

    // MARK: Start question

    func testASkippedStartQuestionIsRememberedAcrossRelaunches() throws {
        var contract = TaskContract(taskID: task, taskTitle: "Marketing")
        XCTAssertTrue(contract.needsStartQuestion)
        contract.askedAt = t0
        var book = DriftBook()
        book.save(contract)
        let back = try JSONDecoder().decode(DriftBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(back.contracts[task]?.needsStartQuestion, false, "a relaunch must not ask again")
        // Contracts saved before askedAt existed still decode, and a written workspace never asks.
        let old = try JSONDecoder().decode(TaskContract.self, from: Data(#"{"taskID":"\#(task.uuidString)","sites":["claude.ai"]}"#.utf8))
        XCTAssertNil(old.askedAt)
        XCTAssertFalse(old.needsStartQuestion)
    }

    func testPartOfTheTaskIsKeptPerTask() throws {
        let other = UUID()
        var book = DriftBook()
        var a = marketing
        let figma = ActivitySample(appBundleID: "com.figma.Desktop", appName: "Figma", windowTitle: "Ads v2")
        a.include(figma)
        book.save(a)
        book.save(TaskContract(taskID: other, taskTitle: "Taxes", apps: ["com.apple.Numbers"]))
        let back = try JSONDecoder().decode(DriftBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(DriftClassifier.classify(figma, contract: try XCTUnwrap(back.contracts[task])), .onTask)
        XCTAssertEqual(DriftClassifier.classify(figma, contract: try XCTUnwrap(back.contracts[other])), .offTask,
                       "juggling: one task's learned app isn't another's")
    }

    // MARK: Korean

    func testKoreanParticlesInTheTaskTitleStillMatch() {
        let contract = TaskContract(taskID: task, taskTitle: "마케팅을 정리하기", apps: ["com.notion.id"])
        XCTAssertEqual(contract.topicWords, ["마케팅", "정리"])
        let notes = ActivitySample(appBundleID: "com.apple.Notes", appName: "Notes", windowTitle: "마케팅 채널 메모")
        XCTAssertEqual(DriftClassifier.classify(notes, contract: contract), .onTask)
        // Two-syllable words keep their last syllable even when it looks like a particle.
        XCTAssertEqual(TopicWords.extract("회의 준비"), ["회의", "준비"])
        XCTAssertEqual(TopicWords.extract("데이터를 서버에서"), ["데이터", "서버"])
    }

    func testDecomposedKoreanTitlesMatch() {
        // File names often reach window titles in NFD (jamo), while typed titles are NFC.
        let decomposed = "마케팅 계획.pages".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(decomposed.unicodeScalars), Array("마케팅 계획.pages".unicodeScalars))
        let pages = ActivitySample(appBundleID: "com.apple.iWork.Pages", appName: "Pages", windowTitle: decomposed)
        XCTAssertEqual(DriftClassifier.classify(pages, contract: marketing), .onTask)
        let nfdTask = TaskContract(taskID: task, taskTitle: "마케팅 조사".decomposedStringWithCanonicalMapping, apps: ["x"])
        XCTAssertTrue(TopicWords.overlaps(nfdTask.topicWords, with: "마케팅 채널"))
    }

    // MARK: Away, days, timings

    func testTimeAwayIsNeitherDriftNorCounted() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        let later = t0.addingTimeInterval(600)
        _ = monitor.observe(clinic, verdict: .offTask, at: later)
        _ = monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(60))
        // Stepped away with the clinic tab up (or the lid closed) for 20 minutes.
        monitor.away(at: later.addingTimeInterval(63))
        let back = later.addingTimeInterval(63 + 20 * 60)
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: back), "the drift clock starts over")
        XCTAssertNil(monitor.observe(clinic, verdict: .offTask, at: back.addingTimeInterval(60)))
        XCTAssertNotNil(monitor.observe(clinic, verdict: .offTask, at: back.addingTimeInterval(90)))
        let tally = monitor.end(at: back.addingTimeInterval(90))
        XCTAssertEqual(tally?.offTask, 63 + 90, "the 20 minutes away aren't in the tally")
    }

    func testANewDayStartsTheTallyFromZero() {
        var monitor = DriftMonitor()
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        _ = monitor.observe(doc, verdict: .onTask, at: t0)
        _ = monitor.observe(doc, verdict: .onTask, at: t0.addingTimeInterval(30))
        XCTAssertEqual(monitor.tally?.onTask, 30)
        monitor.startNewTally()
        _ = monitor.observe(doc, verdict: .onTask, at: t0.addingTimeInterval(33))
        XCTAssertEqual(monitor.tally?.onTask, 3)
        XCTAssertEqual(monitor.tally?.taskTitle, "Marketing")
    }

    func testYesterdaysTallyIsDroppedEvenWithoutFocusToday() {
        var book = DriftBook()
        var tally = DriftTally(taskTitle: "Marketing")
        tally.drift = ["clinic.co.kr": 300]
        book.record(tally, for: task, dayKey: "2026-10-19")
        book.save(marketing)
        XCTAssertFalse(book.prune(dayKey: "2026-10-19"))
        XCTAssertTrue(book.prune(dayKey: "2026-10-20"))
        XCTAssertTrue(book.tallies.isEmpty, "no site names from yesterday stay on disk")
        XCTAssertNotNil(book.contracts[task], "contracts are your own words and stay")
    }

    func testDefaultTimingsMatchTheDesign() {
        let config = DriftConfig.standard
        XCTAssertEqual(config.offTaskSeconds, 90)
        XCTAssertEqual(config.warmUpSeconds, 5 * 60)
        XCTAssertEqual(config.sampleSeconds, 3)
        XCTAssertEqual(config.unsureSeconds, 4 * 60)
        XCTAssertEqual(config.idleSeconds, 5 * 60)
        XCTAssertEqual(BrowserTabReport.freshSeconds, 45)
        // Tuning is one value: a stricter guard nudges sooner.
        var monitor = DriftMonitor(config: DriftConfig(offTaskSeconds: 30))
        monitor.begin(taskID: task, title: "Marketing", at: t0)
        let later = t0.addingTimeInterval(600)
        _ = monitor.observe(clinic, verdict: .offTask, at: later)
        XCTAssertNotNil(monitor.observe(clinic, verdict: .offTask, at: later.addingTimeInterval(30)))
    }

    // MARK: Browser tab reports

    func testATabReportOnlyStandsInForItsOwnBrowser() {
        let now = t0
        let chrome = BrowserTabReport(host: "reddit.com", title: "r/ADHD", at: now.addingTimeInterval(-5))
        let safari = BrowserTabReport(host: "docs.google.com", title: "Q4 plan", at: now.addingTimeInterval(-20))
        XCTAssertEqual(BrowserTabReport.current(forBrowser: "com.apple.Safari", windowTitle: nil, bridge: chrome, safari: safari, now: now), safari,
                       "Chrome's newer tab must not be read as Safari's")
        XCTAssertEqual(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: nil, bridge: chrome, safari: safari, now: now), chrome)
        XCTAssertNil(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: nil, bridge: nil, safari: safari, now: now))
        XCTAssertNil(BrowserTabReport.current(forBrowser: "com.apple.finder", windowTitle: nil, bridge: chrome, safari: safari, now: now))
    }

    func testAStaleTabReportHoldsOnlyWhileTheWindowStillShowsIt() {
        let now = t0
        let old = BrowserTabReport(host: "docs.google.com", title: "Q4 plan - Google Docs", at: now.addingTimeInterval(-300))
        XCTAssertEqual(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: "Q4 plan - Google Docs - Google Chrome",
                                                bridge: old, safari: nil, now: now), old)
        XCTAssertNil(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: "YouTube - Google Chrome",
                                              bridge: old, safari: nil, now: now))
        XCTAssertNil(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: nil, bridge: old, safari: nil, now: now))
        let untitled = BrowserTabReport(host: "example.com", title: "", at: now.addingTimeInterval(-300))
        XCTAssertNil(BrowserTabReport.current(forBrowser: "com.google.Chrome", windowTitle: "Anything", bridge: untitled, safari: nil, now: now))
    }

    func testTabReportsAreCleaned() {
        XCTAssertNil(BrowserTabReport.make(host: "not a host", title: "x"))
        XCTAssertNil(BrowserTabReport.make(host: nil, title: "x"))
        let report = BrowserTabReport.make(host: "https://www.Docs.Google.com/d/1", title: "  \(String(repeating: "가", count: 300))  ")
        XCTAssertEqual(report?.host, "docs.google.com")
        XCTAssertEqual(report?.title.count, 200)
    }

    func testDriftCopyNamesTaskAndPlace() {
        for tone in NudgeTone.allCases {
            let line = Copy(tone: tone).drift(task: "ScaleMaster marketing", label: "clinic.co.kr", minutes: 4)
            XCTAssertTrue((line.title + line.body).contains("ScaleMaster marketing"))
            XCTAssertTrue(line.body.contains("clinic.co.kr"))
        }
    }
}

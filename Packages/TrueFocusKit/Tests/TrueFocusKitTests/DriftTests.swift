import XCTest
@testable import TrueFocusKit

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
        XCTAssertEqual(DriftClassifier.classify(other, contract: contract), .offTask)
        contract.include(other)
        XCTAssertEqual(contract.apps.filter { $0 == "com.google.Chrome" }.count, 1, "browsers aren't added as whole apps")
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

    func testDriftCopyNamesTaskAndPlace() {
        for tone in NudgeTone.allCases {
            let line = Copy(tone: tone).drift(task: "ScaleMaster marketing", label: "clinic.co.kr", minutes: 4)
            XCTAssertTrue((line.title + line.body).contains("ScaleMaster marketing"))
            XCTAssertTrue(line.body.contains("clinic.co.kr"))
        }
    }
}

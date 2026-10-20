import XCTest
@testable import TrueFocusKit

final class DefaultToneTests: XCTestCase {
    func testDefaultToneIsDirect() {
        XCTAssertEqual(TFSettings().tone, .direct)
        XCTAssertEqual(TFSettings.default.tone, .direct)
        XCTAssertEqual(NudgeContext(mode: .rest, modeStartedAt: nil, now: Date()).tone, .direct)
    }

    func testOldSettingsWithoutAToneGetDirect() throws {
        let old = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"restBaseSeconds":30}"#.utf8))
        XCTAssertEqual(old.tone, .direct)
    }

    func testSavedToneIsKept() throws {
        for tone in NudgeTone.allCases {
            let saved = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"tone":"\#(tone.rawValue)"}"#.utf8))
            XCTAssertEqual(saved.tone, tone)
        }
    }

    func testDefaultCopyIsClean() {
        let copy = Copy(settings: TFSettings())
        for level in 1...3 {
            XCTAssertFalse(copy.restOver(level: level, next: "Deck").title.lowercased().contains("fuck"))
            XCTAssertFalse(copy.idle(level: level, next: "Deck", left: 2).title.lowercased().contains("fuck"))
        }
        XCTAssertFalse(copy.bootOut(site: "X", task: nil).title.lowercased().contains("fuck"))
    }

    func testSavageIsLabelledAsStrongLanguage() {
        XCTAssertEqual(NudgeTone.savage.fullLabel, "Savage · strong language")
        XCTAssertEqual(NudgeTone.direct.fullLabel, "Direct")
        XCTAssertEqual(NudgeTone.savage.note, "Strong language")
    }
}

final class CustomReminderTests: XCTestCase {
    private func copy(_ tone: NudgeTone, _ moment: ReminderMoment, _ text: String?) -> Copy {
        var custom = CustomReminders()
        custom[moment] = text
        return Copy(tone: tone, custom: custom)
    }

    private func copy(_ moment: ReminderMoment, _ text: String?) -> Copy {
        copy(.direct, moment, text)
    }

    // MARK: The override rule

    func testNoCustomTextKeepsTheBuiltInLine() {
        let builtIn = Copy(tone: .direct).restOver(level: 2, next: "Deck")
        XCTAssertEqual(copy(.restOver, nil).restOver(level: 2, next: "Deck"), builtIn)
        XCTAssertEqual(copy(.restOver, "").restOver(level: 2, next: "Deck"), builtIn)
        XCTAssertEqual(Copy(tone: .direct, custom: CustomReminders(restOver: "   \n "))
            .restOver(level: 2, next: "Deck"), builtIn)
    }

    func testShortCustomTextBecomesTheTitleAndKeepsTheBody() {
        let builtIn = Copy(tone: .direct).restOver(level: 2, next: "Deck")
        let line = copy(.restOver, "  Up you get.  ").restOver(level: 2, next: "Deck")
        XCTAssertEqual(line.title, "Up you get.")
        XCTAssertEqual(line.body, builtIn.body)
    }

    func testLongCustomTextBecomesTheBodyUnderTheToneTitle() {
        let text = "Get up, stretch, and open the deck before the coffee goes cold."
        XCTAssertGreaterThan(text.count, CustomReminders.titleLimit)
        let line = copy(.calm, .stuck, text).stuck(level: 1, task: "Deck")
        XCTAssertEqual(line.title, Copy(tone: .calm).stuck(level: 1, task: "Deck").title)
        XCTAssertEqual(line.body, text)
    }

    func testTheLimitIsFortyCharactersAfterFillingInTheTask() {
        let forty = String(repeating: "a", count: 40)
        XCTAssertEqual(copy(.idle, forty).idle(level: 1, next: nil, left: 2).title, forty)
        let fortyOne = forty + "b"
        XCTAssertEqual(copy(.idle, fortyOne).idle(level: 1, next: nil, left: 2).body, fortyOne)
        // "Back to {task}" is short, but a long task title pushes it into the body.
        let long = copy(.paused, "Back to {task}").paused(level: 1, task: "Rewrite the onboarding emails for the beta")
        XCTAssertEqual(long.body, "Back to Rewrite the onboarding emails for the beta")
        XCTAssertEqual(long.title, Copy(tone: .direct).paused(level: 1, task: nil).title)
    }

    func testCustomTextAppliesAtEveryLevelOfItsMomentOnly() {
        let c = copy(.savage, .restOver, "Up.")
        for level in 1...3 {
            XCTAssertEqual(c.restOver(level: level, next: "Deck").title, "Up.")
            XCTAssertEqual(c.restOver(level: level, next: "Deck").body,
                           Copy(tone: .savage).restOver(level: level, next: "Deck").body)
        }
        XCTAssertEqual(c.stuck(level: 3, task: "Deck"), Copy(tone: .savage).stuck(level: 3, task: "Deck"))
    }

    func testEveryMomentCanBeOverridden() {
        for moment in ReminderMoment.allCases {
            let c = copy(.savage, moment, "Mine: {task}")
            XCTAssertEqual(c.sample(moment, task: "Deck").title, "Mine: Deck", moment.rawValue)
            // Every other moment stays built in.
            for other in ReminderMoment.allCases where other != moment {
                XCTAssertEqual(c.sample(other, task: "Deck"), Copy(tone: .savage).sample(other, task: "Deck"),
                               "\(moment.rawValue) leaked into \(other.rawValue)")
            }
        }
    }

    func testEachMomentReachesItsSurface() {
        var custom = CustomReminders()
        for moment in ReminderMoment.allCases { custom[moment] = moment.rawValue }
        let c = Copy(tone: .direct, custom: custom)
        XCTAssertEqual(c.restOver(level: 3, next: nil).title, "restOver")
        XCTAssertEqual(c.stuck(level: 2, task: nil).title, "stuck")
        XCTAssertEqual(c.stillOnIt(task: nil).title, "longFocus")
        XCTAssertEqual(c.idle(level: 1, next: nil, left: 1).title, "idle")
        XCTAssertEqual(c.paused(level: 3, task: nil).title, "paused")
        XCTAssertEqual(c.bootOut(site: "X", task: nil).title, "bootOut")
        XCTAssertEqual(c.shield(during: .think, task: "Deck", minutesIn: nil).title, "shield")
        XCTAssertEqual(c.shield(during: .think, task: "Deck", minutesIn: nil).body,
                       c.shieldSubtitle(task: "Deck", minutesIn: nil))
        XCTAssertEqual(c.budgetWarning(minutesLeft: 2, task: nil).title, "budgetWarning")
        XCTAssertEqual(c.budgetSpent(subtitle: "Locked.", task: nil), Copy.Line(title: "budgetSpent", body: "Locked."))
        XCTAssertEqual(c.passEnding.title, "passEnding")
        XCTAssertEqual(c.passEnding(task: "Deck").title, "passEnding")
    }

    func testNudgePlannerUsesCustomReminders() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let nudges = NudgePlanner.plan(NudgeContext(mode: .rest, modeStartedAt: now,
                                                    plannedRestEnd: now.addingTimeInterval(45),
                                                    nextTaskTitle: "Deck", tone: .savage,
                                                    customReminders: CustomReminders(restOver: "Back to {task}."),
                                                    now: now))
        XCTAssertEqual(Set(nudges.map(\.title)), ["Back to Deck."])
        XCTAssertFalse(nudges.contains { $0.title.contains("fuck") })
    }

    func testCopyFromSettingsCarriesToneAndWords() {
        var settings = TFSettings()
        settings.tone = .calm
        settings.customReminders.bootOut = "Out you go."
        let c = Copy(settings: settings)
        XCTAssertEqual(c.tone, .calm)
        XCTAssertEqual(c.bootOut(site: nil, task: "Deck"),
                       Copy.Line(title: "Out you go.", body: Copy(tone: .calm).bootOut(site: nil, task: "Deck").body))
        // Copy(tone:) is still the built-in voice.
        XCTAssertEqual(Copy(tone: .calm).bootOut(site: nil, task: nil).title, "That's enough scrolling")
    }

    // MARK: {task}

    func testTaskPlaceholder() {
        XCTAssertEqual(CustomReminders.fill("Back to {task}.", task: "  Deck  "), "Back to Deck.")
        XCTAssertEqual(CustomReminders.fill("Back to {task}.", task: nil), "Back to your next task.")
        XCTAssertEqual(CustomReminders.fill("Back to {task}.", task: "   "), "Back to your next task.")
        XCTAssertEqual(CustomReminders.fill("{Task} — {TASK}", task: "Deck"), "Deck — Deck")
        XCTAssertEqual(CustomReminders.fill("No placeholder", task: "Deck"), "No placeholder")
        XCTAssertEqual(copy(.bootOut, "{task} needs you").bootOut(site: "X", task: "Deck").title, "Deck needs you")
        XCTAssertEqual(copy(.bootOut, "{task} needs you").bootOut(site: "X", task: nil).title, "your next task needs you")
    }

    // MARK: Storage

    func testSettingBlankTextClearsTheMoment() {
        var custom = CustomReminders()
        custom[.stuck] = "Write one line."
        XCTAssertEqual(custom.stuck, "Write one line.")
        XCTAssertFalse(custom.isEmpty)
        custom[.stuck] = "   "
        XCTAssertNil(custom.stuck)
        XCTAssertTrue(custom.isEmpty)
    }

    func testStoredTextIsOneLineAndCapped() {
        var custom = CustomReminders()
        custom[.idle] = "Line one\nline two"
        XCTAssertEqual(custom.idle, "Line one line two")
        custom[.idle] = String(repeating: "x", count: 500)
        XCTAssertEqual(custom.idle?.count, CustomReminders.maxLength)
        var settings = TFSettings()
        settings.customReminders.paused = String(repeating: "y", count: 500)
        settings.customReminders.shield = " "
        settings.normalize()
        XCTAssertEqual(settings.customReminders.paused?.count, CustomReminders.maxLength)
        XCTAssertNil(settings.customReminders.shield)
    }

    func testOldSettingsWithoutCustomRemindersDecode() throws {
        XCTAssertTrue(TFSettings().customReminders.isEmpty)
        let old = try JSONDecoder().decode(TFSettings.self,
                                           from: Data(#"{"tone":"savage","restBaseSeconds":30}"#.utf8))
        XCTAssertEqual(old.customReminders, CustomReminders())
        XCTAssertEqual(old.tone, .savage)
        XCTAssertEqual(old.restBaseSeconds, 30)
    }

    func testDecodingIsTolerantOfJunk() throws {
        // A non-string value or an unknown key drops that one entry, not the rest.
        let json = #"{"tone":"calm","customReminders":{"bootOut":"Out.","stuck":42,"someday":"x"}}"#
        let s = try JSONDecoder().decode(TFSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.tone, .calm)
        XCTAssertEqual(s.customReminders.bootOut, "Out.")
        XCTAssertNil(s.customReminders.stuck)
        // customReminders that isn't an object at all falls back to empty.
        let wrong = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"tone":"calm","customReminders":"hi"}"#.utf8))
        XCTAssertTrue(wrong.customReminders.isEmpty)
        XCTAssertEqual(wrong.tone, .calm)
    }

    func testRoundTrip() throws {
        var settings = TFSettings()
        settings.tone = .savage
        settings.customReminders = CustomReminders(restOver: "Up.", bootOut: "Out of {task}.",
                                                   passEnding: "Wrap it up, then go back to {task}.")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(settings)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(TFSettings.self, from: data), settings)

        // The JSON shape the browser extension reads: settings.customReminders.bootOut.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let reminders = object?["customReminders"] as? [String: Any]
        XCTAssertEqual(reminders?["bootOut"] as? String, "Out of {task}.")
        XCTAssertNil(reminders?["stuck"], "unset moments are left out")
    }

    func testLongFocusWordsSayTheCheckInIsOptIn() {
        // The 75-minute check-in is off by default, so words for it only show once it's on.
        XCTAssertFalse(TFSettings().focusCheckIn)
        XCTAssertTrue(ReminderMoment.longFocus.detail.contains("check-in is on"), ReminderMoment.longFocus.detail)
    }

    func testMomentKeysMatchTheStoredFields() throws {
        var custom = CustomReminders()
        for moment in ReminderMoment.allCases { custom[moment] = "x" }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as? [String: Any]
        XCTAssertEqual(Set(object?.keys.map { $0 } ?? []), Set(ReminderMoment.allCases.map(\.rawValue)))
        for moment in ReminderMoment.allCases {
            XCTAssertFalse(moment.label.isEmpty)
            XCTAssertFalse(moment.detail.isEmpty)
        }
    }
}

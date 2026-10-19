import Foundation
import TrueFocusKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The drift guard's small use of AI, all on-device with Apple's language model:
///
/// - **Judge**: for a window or tab the rules can't place ("unsure"), decide whether it plausibly
///   serves the task. Only names and titles are sent to the model; nothing leaves the Mac.
/// - **Suggest**: when a task starts, offer topic words and likely sites for its start contract.
///
/// Without Apple Intelligence (or with the setting off) both return nil and the rules decide.
@MainActor
final class DriftJudge {
    static let shared = DriftJudge()

    private var cache: [String: DriftVerdict] = [:]
    private var inFlight: Set<String> = []

    var isAvailable: Bool { TaskExtractor.usesOnDeviceModel }

    /// A cached verdict for this sample, if the model has already judged it for this task.
    func cachedVerdict(for sample: ActivitySample, contract: TaskContract) -> DriftVerdict? {
        cache[key(sample, contract)]
    }

    /// Judges in the background; the verdict lands in the cache for the next tick.
    func judge(_ sample: ActivitySample, contract: TaskContract) {
        let key = key(sample, contract)
        guard isAvailable, cache[key] == nil, !inFlight.contains(key), inFlight.count < 2 else { return }
        inFlight.insert(key)
        Task {
            let verdict = await Self.askModel(sample, contract: contract)
            inFlight.remove(key)
            if let verdict {
                if cache.count > 500 { cache.removeAll() }
                cache[key] = verdict
            }
        }
    }

    func forget(taskID: UUID) {
        cache = cache.filter { !$0.key.hasPrefix(taskID.uuidString) }
    }

    private func key(_ sample: ActivitySample, _ contract: TaskContract) -> String {
        "\(contract.taskID.uuidString)#\(contract.updatedAt.timeIntervalSince1970)#\(sample.cacheKey)"
    }

    struct Ideas {
        var keywords: [String]
        var sites: [String]
    }

    /// Topic words and likely sites for a task, from its title and first move.
    func suggest(title: String, firstMove: String?) async -> Ideas? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You help someone describe what doing a task looks like on their computer, so a focus app \
            can tell when they drift away from it. Given a task, list short topic words that would \
            appear in the titles of documents, chats, searches and web pages used for it (include the \
            same language the task is written in, and English), and well-known websites (bare host \
            names like docs.google.com) the task is commonly done on. Never invent specifics you can't \
            infer; prefer fewer, accurate items.
            """)
        var prompt = "Task: \(title)"
        if let firstMove, !firstMove.isEmpty { prompt += "\nFirst step: \(firstMove)" }
        do {
            let response = try await session.respond(to: prompt, generating: ContractIdeas.self)
            let words = response.content.keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && $0.count <= 30 }
            let sites = response.content.sites.compactMap(Blocklist.normalizedSite)
            return Ideas(keywords: Array(Self.unique(words).prefix(8)), sites: Array(Self.unique(sites).prefix(6)))
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func askModel(_ sample: ActivitySample, contract: TaskContract) async -> DriftVerdict? {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: """
            You decide whether what a person has open on their computer plausibly serves the task they \
            said they're working on. Research, reference, tools and communication about the task count \
            as on task. Unrelated shopping, entertainment, news, personal browsing, or a different \
            project count as off task. When genuinely unclear, say on task.
            """)
        var lines = ["Task: \(contract.taskTitle)"]
        if let firstMove = contract.firstMove, !firstMove.isEmpty { lines.append("First step: \(firstMove)") }
        if !contract.keywords.isEmpty { lines.append("Topic words: \(contract.keywords.joined(separator: ", "))") }
        lines.append("Open now: \(sample.appName ?? sample.appBundleID ?? "an app")")
        if let host = sample.host { lines.append("Website: \(host)") }
        if let title = sample.pageTitle ?? sample.windowTitle { lines.append("Title: \(String(title.prefix(160)))") }
        do {
            let response = try await session.respond(to: lines.joined(separator: "\n"), generating: DriftJudgement.self)
            return response.content.onTask ? .onTask : .offTask
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

#if canImport(FoundationModels)
@Generable
struct DriftJudgement {
    @Guide(description: "True if what's open plausibly serves the task; false if it's clearly something else.")
    var onTask: Bool
}

@Generable
struct ContractIdeas {
    @Guide(description: "Up to 8 short topic words that would appear in titles while doing this task.")
    var keywords: [String]
    @Guide(description: "Up to 5 well-known website host names where this task is commonly done, like docs.google.com.")
    var sites: [String]
}
#endif

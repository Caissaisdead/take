import Foundation
import FoundationModels
import ManuscriptKit

/// What Untangle hands back: a fixed template, never prose for the draft.
struct Untangling: Hashable {
    /// The one-sentence job of the scene in the book.
    var job: String
    /// How the value shifts from the start to the end.
    var shift: String
    /// Five to eight beats.
    var beats: [String]
    /// What the reader must know or feel by the end.
    var reader: String
    /// At most three questions only the writer can answer.
    var questions: [String]
    /// The smallest version of the scene, about 150 words.
    var sketch: String
    /// How much of the scene the model read, when not all of it.
    var note: String?
}

enum EngineError: LocalizedError {
    case notReady(String)
    case refused
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notReady(let why): return why
        case .refused: return "The model declined this scene."
        case .failed(let why): return why
        }
    }
}

/// Untangle on Apple's on-device model. The window is a few thousand tokens,
/// so a long scene is read from the top as far as it fits and the result says
/// so. Nothing leaves the Mac.
struct Untangler {
    /// Documented floor for the on-device model, used before the system
    /// reports a real one (it reports zero until the model has loaded).
    static let assumedContextWindow = 4_096
    /// Kept for the answer and the instructions.
    static let reserved = 1_100

    var contextWindow: Int {
        let reported = SystemLanguageModel.default.contextSize
        return reported > 0 ? reported : Self.assumedContextWindow
    }

    /// Why the model cannot run, or nil when it can.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in System Settings."
            case .modelNotReady: return "Apple Intelligence is still downloading its model."
            @unknown default: return "Apple Intelligence is unavailable on this Mac."
            }
        @unknown default:
            return "Apple Intelligence is unavailable on this Mac."
        }
    }

    /// Below this the model has nothing to read and makes a scene up.
    static let minimumWords = 40

    func untangle(scene title: String, text: String) async throws -> Untangling {
        if let reason = unavailableReason { throw EngineError.notReady(reason) }
        guard Prose.wordCount(text) >= Self.minimumWords else {
            throw EngineError.notReady("The scene has too little text to untangle. Write a few paragraphs first.")
        }
        let (body, note) = Self.fit(text, within: contextWindow - Self.reserved)
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = "Scene title: \(title)\n\n\(body)"
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedUntangling.self,
                options: GenerationOptions(maximumResponseTokens: 700))
            let content = response.content
            return Untangling(
                job: Self.clean(content.job),
                shift: Self.clean(content.shift),
                beats: content.beats.map(Self.clean).filter { !$0.isEmpty },
                reader: Self.clean(content.reader),
                questions: Array(content.questions.map(Self.clean).filter { !$0.isEmpty }.prefix(3)),
                sketch: Self.clean(content.sketch),
                note: note)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw EngineError.failed("The scene is too long for the on-device model even after trimming.")
            case .refusal, .guardrailViolation: throw EngineError.refused
            default: throw EngineError.failed(error.localizedDescription)
            }
        } catch {
            throw EngineError.failed(error.localizedDescription)
        }
    }

    /// Whole paragraphs from the top until the budget is spent, and a note
    /// saying so when that is not all of them.
    static func fit(_ text: String, within budget: Int) -> (String, String?) {
        let cut = Prose.prefix(text, withinTokens: budget)
        guard !cut.whole else { return (Prose.join(cut.kept), nil) }
        return (Prose.join(cut.kept), "Read the first \(cut.kept.count) of \(cut.total) paragraphs; the on-device model holds about \(budget) tokens.")
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let instructions = """
    You are a story editor reading one scene of a novel in draft. Answer only from what is on the page. \
    Say what the scene is for in the book, not what happens in it. Be concrete and short. \
    Ask a question only when the writer alone can answer it; three at most, none if none are needed. \
    The sketch is the smallest version of this same scene, about 150 words, in plain prose, not a summary of it.
    """
}

@Generable
private struct GeneratedUntangling {
    @Guide(description: "The job this scene does for the book, in one sentence.")
    var job: String

    @Guide(description: "The value that shifts across the scene, from what at the start to what at the end. One sentence.")
    var shift: String

    @Guide(description: "The scene's beats in order, five to eight, one short line each.")
    var beats: [String]

    @Guide(description: "What the reader must know or feel by the end of the scene. One or two sentences.")
    var reader: String

    @Guide(description: "Questions only the writer can answer, at most three. Empty if none are needed.")
    var questions: [String]

    @Guide(description: "The smallest version of this scene, about 150 words of prose.")
    var sketch: String
}

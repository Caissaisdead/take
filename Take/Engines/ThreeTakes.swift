import Foundation
import ManuscriptKit

/// Three takes of one scene, each on its own angle, written one after another
/// so the later ones can be told what the earlier ones did.
enum ThreeTakes {
    struct Angle: Identifiable, Hashable {
        let id: String
        let name: String
        let card: String
    }

    static let angles: [Angle] = [
        Angle(id: "A", name: "Late in, early out",
              card: "Enter the scene as late as the story allows and leave before it resolves. Cut the arrival and the departure; start inside the pressure."),
        Angle(id: "B", name: "The withheld fact",
              card: "Hold back the one piece of information the scene turns on until the last line. Everything before it should read differently once it lands."),
        Angle(id: "C", name: "One continuous action",
              card: "Tell the whole scene as a single continuous action in one place, with no scene break, no summary and no jump in time. Let dialogue and gesture carry every beat."),
    ]

    /// What one take is written from. The neighbours give the voice; the
    /// untangling gives the beats; the draft gives what to keep.
    struct Brief {
        var manuscriptTitle: String
        var sceneTitle: String
        var draft: String
        var before: String?
        var after: String?
        var untangling: Untangling?
    }

    /// Word budget for each neighbour scene, taken from the end of the one
    /// before and the start of the one after.
    static let neighbourWords = 1_200

    static let system = """
    You are continuing a novel in draft. Write the scene asked for so that it would be indistinguishable in a blind read from the pages around it: same point of view, tense, register, sentence rhythm and dialogue habits as the neighbouring prose. \
    Do not summarise at the end, do not have characters state their feelings, do not resolve a tension the beats leave open, and avoid tidy button endings and rhetorical triplets. \
    Keep the scene's job and beats; change how it is told. Deliver at least one beat through action or subtext rather than dialogue. \
    Add no named characters, places or facts that the material does not contain. \
    Answer with the prose of the scene only: plain paragraphs separated by blank lines, Markdown *emphasis* where the manuscript uses it, no title, no preamble, no notes.
    """

    /// `previous` carries each earlier take with the angle it was written on,
    /// so a take that failed leaves no gap for the names to slip into.
    static func prompt(for brief: Brief, angle: Angle, previous: [(angle: Angle, text: String)]) -> String {
        var parts: [String] = []
        parts.append("Manuscript: \(brief.manuscriptTitle)\nScene: \(brief.sceneTitle)")
        if let before = brief.before, !before.isEmpty {
            parts.append("The end of the scene before it:\n\n\(Prose.tail(before, words: neighbourWords))")
        }
        if let after = brief.after, !after.isEmpty {
            parts.append("The start of the scene after it:\n\n\(Prose.head(after, words: neighbourWords))")
        }
        if let u = brief.untangling {
            var sheet = "What the scene is for: \(u.job)\nThe shift: \(u.shift)\nBeats:\n"
            sheet += u.beats.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            sheet += "\nThe reader must: \(u.reader)"
            parts.append("The beat sheet:\n\n\(sheet)")
        }
        if brief.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("There is no draft of this scene yet; write it from the beat sheet and the neighbours.")
        } else {
            parts.append("The current draft of the scene:\n\n\(brief.draft)")
        }
        for take in previous {
            parts.append("A take already written (\(take.angle.name)); do not reuse its opening image, its structure or its last line:\n\n\(take.text)")
        }
        parts.append("The angle for this take, \(angle.id), \(angle.name): \(angle.card)\n\nWrite the scene.")
        return parts.joined(separator: "\n\n---\n\n")
    }
}

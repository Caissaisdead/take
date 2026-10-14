import Foundation

/// How both sides stand when main cannot simply move forward: what this side
/// wrote that the remote does not have, scene by scene.
public struct PullDivergence: Equatable, Sendable {
    public let localMain: ObjectID
    public let remoteMain: ObjectID
    /// Where the two last agreed; nil when their histories are unrelated.
    public let base: ObjectID?
    /// Scenes the remote has whose text this side changed: kept as takes.
    public let changed: [SceneRef]
    /// Scenes the remote does not have that this side added or changed: put
    /// back on main with this side's text.
    public let added: [SceneRef]
}

/// What a pull did.
public struct PullResult: Equatable, Sendable {
    public enum Main: Equatable, Sendable {
        case alreadyUpToDate
        /// The remote has no main yet; a backup puts this draft there.
        case remoteEmpty
        /// Only this side moved; nothing to pull.
        case ahead(commits: Int)
        case fastForwarded(commits: Int)
        /// Both sides moved. Main is untouched; `keepMineAsTakes` settles it.
        case diverged(PullDivergence)
    }

    /// A remote take or milestone that met a different local history under
    /// the same name and came in numbered.
    public struct Clash: Equatable, Sendable {
        public let remote: String
        public let local: String
    }

    public let main: Main
    /// Takes, discarded takes and milestones created or moved here, by ref.
    public let brought: [String]
    public let renamed: [Clash]
}

extension ProjectStore {
    /// Where the remote's main stood at the last pull.
    public static let remoteMainRef = "refs/remotes/origin/main"
    /// Where the remote's takes and milestones land before they are settled.
    static let stagingPrefix = "refs/remotes/origin/pull/"

    // MARK: - Clone

    /// Clones the project at `url` into `folder`, then brings every take,
    /// discarded take and milestone across. Blocks for the transfer; call it
    /// off the main thread. The folder is left for the caller to remove when
    /// this throws.
    public static func clone(from url: String, to folder: URL, token: String?, author: Signature) throws -> ProjectStore {
        let store = ProjectStore(repository: try Repository.clone(from: url, to: folder, token: token), author: author)
        _ = try store.manifest()
        _ = try store.syncRefs(from: url, token: token)
        return store
    }

    // MARK: - Pull

    /// Fetches the remote and moves main forward when it can. Takes and
    /// milestones come across whatever main does. When both sides moved, main
    /// is left alone and the divergence comes back for the writer to see.
    /// Opens its own repository so it can run off the main thread while the
    /// app's store stays where it is; the app calls `reload()` afterwards.
    public static func pull(projectAt folder: URL, from url: String, token: String?) throws -> PullResult {
        let store = ProjectStore(repository: try Repository.open(at: folder), author: Signature(name: "pull", email: "pull@localhost"))
        let local = try store.mainHead()
        let sync = try store.syncRefs(from: url, token: token)
        guard let remote = sync.remoteMain else {
            return PullResult(main: .remoteEmpty, brought: sync.brought, renamed: sync.renamed)
        }
        let main: PullResult.Main
        if local == remote {
            main = .alreadyUpToDate
        } else if try store.repository.isAncestor(local, of: remote) {
            let commits = try store.repository.countCommits(from: remote, excluding: local)
            try store.repository.checkoutTree(of: remote)
            try store.repository.updateRef(mainRef, to: remote, message: "pull: fast-forward")
            main = .fastForwarded(commits: commits)
        } else if try store.repository.isAncestor(remote, of: local) {
            main = .ahead(commits: try store.repository.countCommits(from: local, excluding: remote))
        } else {
            main = .diverged(try store.divergence(local: local, remote: remote))
        }
        return PullResult(main: main, brought: sync.brought, renamed: sync.renamed)
    }

    /// Settles a divergence: main becomes the remote's and the files follow;
    /// every scene this side changed becomes a take named "<device> <date>"
    /// holding this side's text, begun from the new main, so Compare shows
    /// it against what the remote wrote and Keep puts it back in one step.
    /// Scenes the remote never had go back on main. Synopses, notes and order
    /// follow the remote. Refuses when main or the remote moved since the
    /// divergence was read.
    @discardableResult
    public func keepMineAsTakes(_ divergence: PullDivergence, device: String) throws -> [Take] {
        guard try mainHead() == divergence.localMain,
              try repository.resolve(Self.remoteMainRef) == divergence.remoteMain else {
            throw ProjectStoreError.pullStale
        }
        let before = try manifest(at: divergence.localMain)
        var texts: [SceneID: String] = [:]
        for scene in divergence.changed + divergence.added {
            texts[scene.id] = try text(of: try entry(scene.path, at: divergence.localMain)?.id)
        }

        try repository.checkoutTree(of: divergence.remoteMain)
        try repository.updateRef(Self.mainRef, to: divergence.remoteMain, message: "pull: set main to the remote's")
        try reload()

        let now = try manifest()
        for scene in divergence.added {
            let chapter = before.chapter(containing: scene.id)?.id
            let destination = chapter.flatMap { now.chapter($0) == nil ? nil : $0 }
            try addScene(title: scene.title, toChapter: destination, text: texts[scene.id] ?? "", id: scene.id,
                         synopsis: scene.synopsis, notes: scene.notes, message: "Bring \(Self.label(scene.title)) from \(device)")
        }
        let name = "\(device) \(Self.pullName.string(from: clock()))"
        var takes: [Take] = []
        for scene in divergence.changed {
            let take = try createTake(for: scene.id, name: name)
            takes.append(try saveTake(take, text: texts[scene.id] ?? ""))
        }
        return takes
    }

    /// The date in a take's name: "14 Oct 2026, 15:04", in the device's zone.
    static let pullName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    // MARK: - Plumbing

    /// Lists the remote, fetches what this side lacks and settles each take
    /// and milestone against its local counterpart. Returns what was brought
    /// in, what came in renamed, and where the remote's main stands (nil
    /// when it has none).
    func syncRefs(from url: String, token: String?) throws -> (brought: [String], renamed: [PullResult.Clash], remoteMain: ObjectID?) {
        var refspecs: [String] = []
        var staged: [(local: String, staged: String)] = []
        var remoteMain: ObjectID?
        for ref in try repository.remoteRefs(at: url, token: token) {
            if ref.name == Self.mainRef {
                remoteMain = ref.id
                if try repository.resolve(Self.remoteMainRef) != ref.id {
                    refspecs.append("+\(ref.name):\(Self.remoteMainRef)")
                }
                continue
            }
            guard Self.backupPrefixes.contains(where: { ref.name.hasPrefix($0) }) else { continue }
            if try repository.resolve(ref.name) == ref.id { continue }
            let stage = Self.stagingPrefix + ref.name.dropFirst("refs/".count)
            refspecs.append("+\(ref.name):\(stage)")
            staged.append((ref.name, stage))
        }
        if !refspecs.isEmpty {
            try repository.fetch(from: url, refspecs: refspecs, token: token)
        }

        var brought: [String] = []
        var renamed: [PullResult.Clash] = []
        for item in staged {
            defer { try? repository.deleteRef(item.staged) }
            guard let theirs = try repository.resolve(item.staged) else { continue }
            guard let mine = try repository.resolve(item.local) else {
                try repository.updateRef(item.local, to: theirs, message: "pull")
                brought.append(item.local)
                continue
            }
            if mine == theirs { continue }
            // A tag points at a tag object, which has no ancestry; two
            // milestones under one name are two milestones.
            if !item.local.hasPrefix(Self.milestonesPrefix) {
                if try repository.isAncestor(mine, of: theirs) {
                    try repository.updateRef(item.local, to: theirs, message: "pull")
                    brought.append(item.local)
                    continue
                }
                if try repository.isAncestor(theirs, of: mine) { continue }
            }
            let free = try freeRef(for: item.local)
            try repository.updateRef(free, to: theirs, message: "pull")
            renamed.append(PullResult.Clash(remote: item.local, local: free))
            brought.append(free)
        }
        return (brought, renamed, remoteMain)
    }

    /// A ref beside `ref` for the same name, numbered past what is there.
    private func freeRef(for ref: String) throws -> String {
        if ref.hasPrefix(Self.milestonesPrefix) {
            let taken = Set(try repository.refs(withPrefix: Self.milestonesPrefix))
            return Self.unique(ref) { taken.contains($0) }
        }
        guard let slash = ref.lastIndex(of: "/") else { return ref }
        let prefix = String(ref[...slash])
        return try freeRef(named: Self.takeName(fromRef: ref, prefix: prefix), under: prefix)
    }

    /// What this side wrote that the remote lacks, scene by scene.
    func divergence(local: ObjectID, remote: ObjectID) throws -> PullDivergence {
        let base = try repository.mergeBase(local, remote)
        let mine = try manifest(at: local)
        let theirs = try manifest(at: remote)
        let ours = try base.map { try manifest(at: $0) }
        var changed: [SceneRef] = []
        var added: [SceneRef] = []
        for scene in mine.scenes {
            let localBlob = try entry(scene.path, at: local)?.id
            let baseBlob = try ours?.scene(scene.id).flatMap { try entry($0.path, at: base!)?.id }
            guard let remoteScene = theirs.scene(scene.id) else {
                // The remote never had it, or removed it: this side's text
                // goes back on main unless this side left it as it was.
                if localBlob != baseBlob { added.append(scene) }
                continue
            }
            let remoteBlob = try entry(remoteScene.path, at: remote)?.id
            if localBlob != baseBlob && localBlob != remoteBlob { changed.append(scene) }
        }
        return PullDivergence(localMain: local, remoteMain: remote, base: base, changed: changed, added: added)
    }
}

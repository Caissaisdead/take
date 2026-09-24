import Clibgit2
import Foundation

/// A thin, owned overlay on libgit2.
///
/// Plumbing only: blobs, trees, commits and refs, plus the index and working tree
/// for the checked-out branch. Merging is never delegated to libgit2's tree merge;
/// the app decides what a merge means and writes the result as a commit with two
/// parents. Every method throws `GitError` on a libgit2 failure.
///
/// Not thread-safe. One instance per repository, used from one actor or queue.
public final class Repository {
    /// The folder holding the working tree; `.git` sits inside it.
    public let workingDirectory: URL
    private let pointer: OpaquePointer

    /// libgit2 counts inits against shutdowns. One init for the whole process and
    /// no shutdown keeps every repository valid for as long as the app runs.
    private static let libgit2: Int32 = git_libgit2_init()

    /// git's well-known empty tree; a folder rebuilt down to this is dropped.
    private static let emptyTree = ObjectID(hex: "4b825dc642cb6eb9a060e54bf8d69288fbee4904")!

    // MARK: - Opening

    /// Creates a non-bare repository at `url`, making the folder if needed.
    /// No initial commit is made and HEAD points at `refs/heads/main`.
    public static func create(at url: URL) throws -> Repository {
        _ = libgit2
        var options = git_repository_init_options()
        try check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)), "git_repository_init_options_init")
        options.flags = GIT_REPOSITORY_INIT_MKPATH.rawValue
        let pointer = try "main".withCString { head in
            options.initial_head = head
            return try lookup("git_repository_init_ext") { git_repository_init_ext($0, url.path, &options) }
        }
        return Repository(pointer: pointer, workingDirectory: url)
    }

    public static func open(at url: URL) throws -> Repository {
        _ = libgit2
        let pointer = try lookup("git_repository_open") { git_repository_open($0, url.path) }
        return Repository(pointer: pointer, workingDirectory: url)
    }

    private init(pointer: OpaquePointer, workingDirectory: URL) {
        self.pointer = pointer
        self.workingDirectory = workingDirectory
    }

    deinit {
        git_repository_free(pointer)
    }

    // MARK: - Objects

    public func writeBlob(_ data: Data) throws -> ObjectID {
        var oid = git_oid()
        try withBytes(data) { bytes, count in
            try check(git_blob_create_from_buffer(&oid, pointer, bytes, count), "git_blob_create_from_buffer")
        }
        return ObjectID(oid)
    }

    public func readBlob(_ id: ObjectID) throws -> Data {
        var oid = id.raw
        let blob = try lookup("git_blob_lookup") { git_blob_lookup($0, pointer, &oid) }
        defer { git_blob_free(blob) }
        let size = Int(git_blob_rawsize(blob))
        guard size > 0, let content = git_blob_rawcontent(blob) else { return Data() }
        return Data(bytes: content, count: size)
    }

    /// The direct entries of a tree, in git's order.
    public func entries(ofTree id: ObjectID) throws -> [TreeEntry] {
        let tree = try lookupTree(id)
        defer { git_tree_free(tree) }
        return (0..<git_tree_entrycount(tree)).compactMap { index in
            guard let entry = git_tree_entry_byindex(tree, index) else { return nil }
            return treeEntry(entry)
        }
    }

    /// The entry at a slash-separated path inside a tree, or nil if absent.
    public func entry(atPath path: String, inTree tree: ObjectID) throws -> TreeEntry? {
        let root = try lookupTree(tree)
        defer { git_tree_free(root) }
        var entry: OpaquePointer?
        let rc = git_tree_entry_bypath(&entry, root, path)
        if rc == GIT_ENOTFOUND.rawValue { return nil }
        try check(rc, "git_tree_entry_bypath")
        defer { git_tree_entry_free(entry) }
        return entry.flatMap(treeEntry)
    }

    /// A new tree equal to `tree` except that `path` maps to `blob`; nil removes
    /// the entry. Intermediate folders are created or rebuilt as needed. A nil
    /// `tree` starts from an empty tree.
    public func tree(replacing path: String, with blob: ObjectID?, in tree: ObjectID?) throws -> ObjectID {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw GitError(operation: "tree(replacing:)", code: -1, message: "empty path")
        }
        return try rebuild(tree, replacing: components[...], with: blob)
    }

    /// One level of `tree(replacing:)`: rebuilds `tree` so that the entry named by
    /// the first component carries the rest of the change, then writes it.
    private func rebuild(_ tree: ObjectID?, replacing components: ArraySlice<String>, with blob: ObjectID?) throws -> ObjectID {
        let source = try tree.map(lookupTree)
        defer { git_tree_free(source) }
        let builder = try lookup("git_treebuilder_new") { git_treebuilder_new($0, pointer, source) }
        defer { git_treebuilder_free(builder) }

        let name = components[components.startIndex]
        let rest = components.dropFirst()
        if rest.isEmpty {
            if let blob {
                var oid = blob.raw
                try check(git_treebuilder_insert(nil, builder, name, &oid, GIT_FILEMODE_BLOB), "git_treebuilder_insert")
            } else if git_treebuilder_get(builder, name) != nil {
                try check(git_treebuilder_remove(builder, name), "git_treebuilder_remove")
            }
        } else {
            var existing: ObjectID?
            if let entry = git_treebuilder_get(builder, name), git_tree_entry_type(entry) == GIT_OBJECT_TREE {
                existing = ObjectID(git_tree_entry_id(entry))
            }
            // Removing from a folder that is not there is already done.
            if blob != nil || existing != nil {
                let subtree = try rebuild(existing, replacing: rest, with: blob)
                if subtree == Self.emptyTree {
                    // git never keeps an empty folder, so neither do we.
                    if existing != nil {
                        try check(git_treebuilder_remove(builder, name), "git_treebuilder_remove")
                    }
                } else {
                    var oid = subtree.raw
                    try check(git_treebuilder_insert(nil, builder, name, &oid, GIT_FILEMODE_TREE), "git_treebuilder_insert")
                }
            }
        }

        var written = git_oid()
        try check(git_treebuilder_write(&written, builder), "git_treebuilder_write")
        return ObjectID(written)
    }

    public func commit(_ id: ObjectID) throws -> CommitInfo {
        let commit = try lookupCommit(id)
        defer { git_commit_free(commit) }
        let author = git_commit_author(commit).pointee
        return CommitInfo(
            id: ObjectID(git_commit_id(commit)),
            parents: (0..<git_commit_parentcount(commit)).map { ObjectID(git_commit_parent_id(commit, $0)) },
            tree: ObjectID(git_commit_tree_id(commit)),
            author: Signature(
                name: String(cString: author.name),
                email: String(cString: author.email),
                time: Date(timeIntervalSince1970: TimeInterval(author.when.time))),
            message: String(cString: git_commit_message(commit)))
    }

    /// Writes a commit. `parents` may be empty (a root) or hold two (a merge).
    /// When `ref` is given it is created or moved to the new commit.
    @discardableResult
    public func createCommit(tree: ObjectID, parents: [ObjectID], author: Signature, message: String, updatingRef ref: String?) throws -> ObjectID {
        let treeObject = try lookupTree(tree)
        defer { git_tree_free(treeObject) }
        var parentObjects: [OpaquePointer?] = []
        defer { parentObjects.forEach { git_commit_free($0) } }
        for parent in parents {
            parentObjects.append(try lookupCommit(parent))
        }
        let signature = try makeSignature(author)
        defer { git_signature_free(signature) }

        var oid = git_oid()
        try parentObjects.withUnsafeMutableBufferPointer { buffer in
            try check(git_commit_create(&oid, pointer, ref, signature, signature, nil, message, treeObject, buffer.count, buffer.baseAddress), "git_commit_create")
        }
        return ObjectID(oid)
    }

    // MARK: - Refs

    /// Resolves a full ref name (`refs/heads/main`, `HEAD`) to a commit, or nil
    /// when the ref does not exist (including an unborn HEAD).
    public func resolve(_ ref: String) throws -> ObjectID? {
        var oid = git_oid()
        let rc = git_reference_name_to_id(&oid, pointer, ref)
        if rc == GIT_ENOTFOUND.rawValue || rc == GIT_EUNBORNBRANCH.rawValue { return nil }
        try check(rc, "git_reference_name_to_id")
        return ObjectID(oid)
    }

    public func updateRef(_ ref: String, to id: ObjectID, message: String) throws {
        var oid = id.raw
        let reference = try lookup("git_reference_create") { git_reference_create($0, pointer, ref, &oid, 1, message) }
        git_reference_free(reference)
    }

    public func deleteRef(_ ref: String) throws {
        try check(git_reference_remove(pointer, ref), "git_reference_remove")
    }

    /// Moves a ref to a new full name, replacing any ref already there.
    func renameRef(_ ref: String, to newName: String) throws {
        let reference = try lookup("git_reference_lookup") { git_reference_lookup($0, pointer, ref) }
        defer { git_reference_free(reference) }
        let renamed = try lookup("git_reference_rename") { git_reference_rename($0, reference, newName, 1, "rename") }
        git_reference_free(renamed)
    }

    /// Full names of every ref starting with `prefix`, sorted.
    public func refs(withPrefix prefix: String) throws -> [String] {
        // libgit2 matches the glob with wildmatch and no flags, so `*` spans slashes.
        var iterator: UnsafeMutablePointer<git_reference_iterator>?
        try check(git_reference_iterator_glob_new(&iterator, pointer, prefix + "*"), "git_reference_iterator_glob_new")
        defer { git_reference_iterator_free(iterator) }
        var names: [String] = []
        while true {
            var name: UnsafePointer<CChar>?
            let rc = git_reference_next_name(&name, iterator)
            if rc == GIT_ITEROVER.rawValue { break }
            try check(rc, "git_reference_next_name")
            if let name { names.append(String(cString: name)) }
        }
        return names.sorted()
    }

    /// Points HEAD symbolically at `refs/heads/<name>` without touching files.
    public func setHead(toBranch name: String) throws {
        try check(git_repository_set_head(pointer, "refs/heads/" + name), "git_repository_set_head")
    }

    // MARK: - History

    /// Commits reachable from `id`, newest first by commit time, at most `limit`.
    public func log(from id: ObjectID, limit: Int) throws -> [CommitInfo] {
        let walker = try lookup("git_revwalk_new") { git_revwalk_new($0, pointer) }
        defer { git_revwalk_free(walker) }
        // Time alone leaves same-second commits in heap order; topological keeps
        // every parent after its children, and time still orders the rest.
        try check(git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue), "git_revwalk_sorting")
        var start = id.raw
        try check(git_revwalk_push(walker, &start), "git_revwalk_push")

        var commits: [CommitInfo] = []
        while commits.count < limit {
            var next = git_oid()
            let rc = git_revwalk_next(&next, walker)
            if rc == GIT_ITEROVER.rawValue { break }
            try check(rc, "git_revwalk_next")
            commits.append(try commit(ObjectID(next)))
        }
        return commits
    }

    public func mergeBase(_ a: ObjectID, _ b: ObjectID) throws -> ObjectID? {
        var one = a.raw
        var two = b.raw
        var base = git_oid()
        let rc = git_merge_base(&base, pointer, &one, &two)
        if rc == GIT_ENOTFOUND.rawValue { return nil }
        try check(rc, "git_merge_base")
        return ObjectID(base)
    }

    // MARK: - Working tree and index

    /// Writes the bytes to `path` under the working directory and stages them.
    public func writeWorkingFile(atPath path: String, data: Data) throws {
        let file = workingDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        let index = try openIndex()
        defer { git_index_free(index) }
        try check(git_index_add_bypath(index, path), "git_index_add_bypath")
        try check(git_index_write(index), "git_index_write")
    }

    /// Deletes the file at `path` and removes it from the index. Git tracks no
    /// folders, so a folder left empty by the deletion goes too, up to the root.
    public func removeWorkingFile(atPath path: String) throws {
        let file = workingDirectory.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        var folder = file.deletingLastPathComponent().standardizedFileURL
        let root = workingDirectory.standardizedFileURL
        while folder.path != root.path, folder.path.hasPrefix(root.path),
              (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try FileManager.default.removeItem(at: folder)
            folder = folder.deletingLastPathComponent()
        }
        let index = try openIndex()
        defer { git_index_free(index) }
        try check(git_index_remove_bypath(index, path), "git_index_remove_bypath")
        try check(git_index_write(index), "git_index_write")
    }

    /// The tree the index currently describes, written to the object database.
    public func writeIndexTree() throws -> ObjectID {
        let index = try openIndex()
        defer { git_index_free(index) }
        var oid = git_oid()
        try check(git_index_write_tree(&oid, index), "git_index_write_tree")
        return ObjectID(oid)
    }

    /// Forces the index and working tree to match HEAD's tree.
    public func checkoutHead() throws {
        var options = git_checkout_options()
        try check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "git_checkout_options_init")
        options.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue
        try check(git_checkout_head(pointer, &options), "git_checkout_head")
    }

    // MARK: - Merge

    /// A line-based three-way merge of one file, in memory. Store one paragraph
    /// per line and this is a paragraph-level merge.
    public func mergeFile(ancestor: Data, ours: Data, theirs: Data) throws -> MergeFileResult {
        var result = git_merge_file_result()
        try withBytes(ancestor) { ancestorBytes, ancestorCount in
            try withBytes(ours) { ourBytes, ourCount in
                try withBytes(theirs) { theirBytes, theirCount in
                    var base = try mergeInput(ancestorBytes, ancestorCount)
                    var mine = try mergeInput(ourBytes, ourCount)
                    var other = try mergeInput(theirBytes, theirCount)
                    var options = git_merge_file_options()
                    try check(git_merge_file_options_init(&options, UInt32(GIT_MERGE_FILE_OPTIONS_VERSION)), "git_merge_file_options_init")
                    try check(git_merge_file(&result, &base, &mine, &other, &options), "git_merge_file")
                }
            }
        }
        defer { git_merge_file_result_free(&result) }
        let content = result.len > 0 ? Data(bytes: result.ptr, count: result.len) : Data()
        return MergeFileResult(isAutomergeable: result.automergeable != 0, content: content)
    }

    // MARK: - Lookups

    private func lookupTree(_ id: ObjectID) throws -> OpaquePointer {
        var oid = id.raw
        return try lookup("git_tree_lookup") { git_tree_lookup($0, pointer, &oid) }
    }

    private func lookupCommit(_ id: ObjectID) throws -> OpaquePointer {
        var oid = id.raw
        return try lookup("git_commit_lookup") { git_commit_lookup($0, pointer, &oid) }
    }

    private func openIndex() throws -> OpaquePointer {
        try lookup("git_repository_index") { git_repository_index($0, pointer) }
    }

    private func makeSignature(_ signature: Signature) throws -> UnsafeMutablePointer<git_signature> {
        var out: UnsafeMutablePointer<git_signature>?
        let seconds = git_time_t(signature.time.timeIntervalSince1970.rounded(.down))
        let offset = Int32(TimeZone.current.secondsFromGMT(for: signature.time) / 60)
        try check(git_signature_new(&out, signature.name, signature.email, seconds, offset), "git_signature_new")
        guard let out else { throw GitError(operation: "git_signature_new", code: -1, message: "libgit2 returned nothing") }
        return out
    }

    /// Submodules have no place in a manuscript, so a commit entry reads as nil.
    private func treeEntry(_ entry: OpaquePointer) -> TreeEntry? {
        let kind: TreeEntry.Kind
        switch git_tree_entry_type(entry) {
        case GIT_OBJECT_BLOB: kind = .blob
        case GIT_OBJECT_TREE: kind = .tree
        default: return nil
        }
        return TreeEntry(name: String(cString: git_tree_entry_name(entry)), id: ObjectID(git_tree_entry_id(entry)), kind: kind)
    }

    private func mergeInput(_ bytes: UnsafeRawPointer, _ count: Int) throws -> git_merge_file_input {
        var input = git_merge_file_input()
        try check(git_merge_file_input_init(&input, UInt32(GIT_MERGE_FILE_INPUT_VERSION)), "git_merge_file_input_init")
        input.ptr = bytes.assumingMemoryBound(to: CChar.self)
        input.size = count
        input.mode = GIT_FILEMODE_BLOB.rawValue
        return input
    }

    /// libgit2 takes (pointer, length) pairs, and an empty Data may hand out a
    /// null pointer; this always gives it a real address.
    private func withBytes<T>(_ data: Data, _ body: (UnsafeRawPointer, Int) throws -> T) throws -> T {
        if data.isEmpty {
            var zero: UInt8 = 0
            return try withUnsafePointer(to: &zero) { try body(UnsafeRawPointer($0), 0) }
        }
        return try data.withUnsafeBytes { try body($0.baseAddress!, $0.count) }
    }
}

/// Throws the last libgit2 error, named after the call, when `rc` is negative.
private func check(_ rc: Int32, _ op: String) throws {
    guard rc < 0 else { return }
    let message = git_error_last().flatMap { $0.pointee.message.map { String(cString: $0) } } ?? "no error message"
    throw GitError(operation: op, code: rc, message: message)
}

/// Runs a libgit2 `(out, ...)` lookup and hands back the pointer it filled in.
private func lookup(_ op: String, _ body: (UnsafeMutablePointer<OpaquePointer?>) -> Int32) throws -> OpaquePointer {
    var out: OpaquePointer?
    try check(body(&out), op)
    guard let out else { throw GitError(operation: op, code: -1, message: "libgit2 returned nothing") }
    return out
}

extension ObjectID {
    fileprivate init(_ oid: git_oid) {
        let digits = Array("0123456789abcdef".utf8)
        var hex: [UInt8] = []
        hex.reserveCapacity(40)
        withUnsafeBytes(of: oid.id) { bytes in
            for byte in bytes {
                hex.append(digits[Int(byte >> 4)])
                hex.append(digits[Int(byte & 0x0f)])
            }
        }
        self.init(hex: String(decoding: hex, as: UTF8.self))!
    }

    fileprivate init(_ oid: UnsafePointer<git_oid>) {
        self.init(oid.pointee)
    }

    /// The id as libgit2 wants it. Parsing cannot fail: `hex` was validated on init.
    fileprivate var raw: git_oid {
        var oid = git_oid()
        precondition(git_oid_fromstr(&oid, hex) == 0)
        return oid
    }
}

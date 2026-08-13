import Foundation

/// `git status --porcelain=v2 --branch` 的解析结果。
public struct RepositoryStatus: Sendable, Equatable {
    public let branch: BranchStatus
    public let entries: [StatusEntry]

    public init(branch: BranchStatus, entries: [StatusEntry]) {
        self.branch = branch
        self.entries = entries
    }

    /// 工作区与 index 都没有需要处理的改动（被忽略的文件不算）。
    public var isClean: Bool {
        entries.allSatisfy { $0.kind == .ignored }
    }

    /// 存在尚未解决的合并冲突。
    public var hasConflicts: Bool {
        entries.contains { $0.kind == .unmerged }
    }
}

/// HEAD 的位置及其与 upstream 的关系。
public struct BranchStatus: Sendable, Equatable {
    /// HEAD 指向的 commit；仓库还没有任何提交时为 nil。
    public let commit: String?
    /// 当前分支名；detached HEAD 时为 nil。
    public let name: String?
    /// upstream 分支名（如 `origin/main`）；未设置时为 nil。
    public let upstream: String?
    /// 领先 upstream 的提交数。
    public let ahead: Int
    /// 落后 upstream 的提交数。
    public let behind: Int

    /// HEAD 没有指向任何分支。
    public var isDetached: Bool { name == nil }

    /// 仓库尚无提交（git 称之为 unborn branch）。此时分支名已确定但 commit 为空。
    public var isUnborn: Bool { commit == nil }

    public init(
        commit: String? = nil,
        name: String? = nil,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0
    ) {
        self.commit = commit
        self.name = name
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}

/// porcelain v2 中 XY 两位各自的取值。
public enum FileStatus: Character, Sendable, Equatable {
    case unmodified = "."
    case modified = "M"
    case fileTypeChanged = "T"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case updatedButUnmerged = "U"
}

/// 一个文件在 index 与工作区中的状态。
public struct StatusEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case ordinary
        case renamed
        case copied
        case unmerged
        case untracked
        case ignored
    }

    public let kind: Kind
    /// 相对仓库根目录的路径。
    public let path: String
    /// 重命名/复制的来源路径，其余情况为 nil。
    public let originalPath: String?
    /// index 相对 HEAD 的状态（XY 的 X 位）。
    public let indexStatus: FileStatus
    /// 工作区相对 index 的状态（XY 的 Y 位）。
    public let workTreeStatus: FileStatus
    /// 重命名/复制的相似度百分比（0–100）。
    public let similarity: Int?
    /// 该条目是 submodule 时的子状态，否则为 nil。
    public let submodule: SubmoduleState?

    public init(
        kind: Kind,
        path: String,
        originalPath: String? = nil,
        indexStatus: FileStatus = .unmodified,
        workTreeStatus: FileStatus = .unmodified,
        similarity: Int? = nil,
        submodule: SubmoduleState? = nil
    ) {
        self.kind = kind
        self.path = path
        self.originalPath = originalPath
        self.indexStatus = indexStatus
        self.workTreeStatus = workTreeStatus
        self.similarity = similarity
        self.submodule = submodule
    }

    /// index 中有待提交的改动。
    public var hasStagedChanges: Bool {
        switch kind {
        case .ordinary, .renamed, .copied: indexStatus != .unmodified
        case .unmerged, .untracked, .ignored: false
        }
    }

    /// 工作区有尚未暂存的改动。冲突文件永远算作待处理。
    public var hasUnstagedChanges: Bool {
        switch kind {
        case .ordinary, .renamed, .copied: workTreeStatus != .unmodified
        case .unmerged: true
        case .untracked, .ignored: false
        }
    }
}

/// porcelain v2 的 `<sub>` 字段（形如 `S.M.`）描述的 submodule 子状态。
public struct SubmoduleState: Sendable, Equatable {
    /// submodule 指向的 commit 发生了变化。
    public let commitChanged: Bool
    /// submodule 工作区有已跟踪文件的改动。
    public let hasModifiedContent: Bool
    /// submodule 工作区有未跟踪文件。
    public let hasUntrackedContent: Bool

    public init(commitChanged: Bool, hasModifiedContent: Bool, hasUntrackedContent: Bool) {
        self.commitChanged = commitChanged
        self.hasModifiedContent = hasModifiedContent
        self.hasUntrackedContent = hasUntrackedContent
    }
}

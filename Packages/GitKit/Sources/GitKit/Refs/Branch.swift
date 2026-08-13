import Foundation

/// 一个分支引用。
public struct Branch: Sendable, Equatable, Identifiable {

    public var id: String { fullName }

    /// 完整引用名，如 `refs/heads/main` 或 `refs/remotes/origin/main`。
    public let fullName: String
    /// 界面显示用的短名，如 `main` 或 `origin/main`。
    public let name: String
    public let commit: String

    /// HEAD 当前指向这个分支。
    public let isCurrent: Bool
    /// 远程跟踪分支（`refs/remotes/*`），不可直接提交。
    public let isRemote: Bool

    /// upstream 的短名，如 `origin/main`；未设置时为 nil。
    public let upstream: String?
    public let tracking: TrackingStatus

    public let lastCommitDate: Date?
    public let lastCommitSubject: String

    public init(
        fullName: String,
        name: String,
        commit: String,
        isCurrent: Bool,
        isRemote: Bool,
        upstream: String?,
        tracking: TrackingStatus,
        lastCommitDate: Date?,
        lastCommitSubject: String
    ) {
        self.fullName = fullName
        self.name = name
        self.commit = commit
        self.isCurrent = isCurrent
        self.isRemote = isRemote
        self.upstream = upstream
        self.tracking = tracking
        self.lastCommitDate = lastCommitDate
        self.lastCommitSubject = lastCommitSubject
    }
}

/// 分支相对其 upstream 的领先/落后情况。
public struct TrackingStatus: Sendable, Equatable {

    public let ahead: Int
    public let behind: Int

    /// upstream 已在远程被删除（git 报告 `[gone]`）。
    ///
    /// 这个状态值得单独标记：分支还留着 upstream 配置，但推送会失败，
    /// 界面需要提示用户清理或重设。
    public let isGone: Bool

    public static let notTracking = TrackingStatus(ahead: 0, behind: 0, isGone: false)

    /// 与 upstream 完全同步。
    public var isInSync: Bool { ahead == 0 && behind == 0 && !isGone }
    /// 存在分叉：两边都有对方没有的提交，直接 push 会被拒。
    public var hasDiverged: Bool { ahead > 0 && behind > 0 }

    public init(ahead: Int, behind: Int, isGone: Bool) {
        self.ahead = ahead
        self.behind = behind
        self.isGone = isGone
    }
}

/// 一个 tag 引用。
public struct Tag: Sendable, Equatable, Identifiable {

    public var id: String { name }

    public let name: String
    /// 指向的 commit。附注 tag 已经解引用到 commit，不是 tag 对象本身。
    public let commit: String
    /// 附注 tag 自身的对象 hash；轻量 tag 为 nil。
    public let tagObject: String?

    /// 打 tag 的人；轻量 tag 没有这个信息。
    public let tagger: Signature?
    /// 附注 tag 的说明；轻量 tag 为 nil（它没有自己的消息）。
    public let message: String?
    public let date: Date?

    /// 附注 tag（`git tag -a`）。工程规范要求发布一律用附注 tag。
    public var isAnnotated: Bool { tagObject != nil }

    public init(
        name: String,
        commit: String,
        tagObject: String?,
        tagger: Signature?,
        message: String?,
        date: Date?
    ) {
        self.name = name
        self.commit = commit
        self.tagObject = tagObject
        self.tagger = tagger
        self.message = message
        self.date = date
    }
}

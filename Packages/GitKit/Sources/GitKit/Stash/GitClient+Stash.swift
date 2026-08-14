import Foundation

extension GitClient {

    /// 读出 stash 栈。
    public func stashList(in repository: URL) async throws -> [StashEntry] {
        let result = try await run(
            ["stash", "list", "--format=%gd%x1f%s%x1f%ct%x1f%H", "-z"],
            in: repository,
            allowsOptionalLocks: false
        )
        return StashParser.parse(result.standardOutput)
    }

    /// 某一条 stash 里改了哪些文件。
    ///
    /// **必须带 `--include-untracked`。** 不带的话，一条只装着未跟踪文件的 stash
    /// 会返回空输出且退出码为 0——界面上就成了「这条 stash 是空的」，
    /// 而它其实好好装着东西。这是实测出来的，不带这个参数的版本看不出任何异常。
    public func stashFiles(at hash: String, in repository: URL) async throws -> [CommitFileChange] {
        let result = try await run(
            ["stash", "show", "--name-status", "--include-untracked", "-z", hash],
            in: repository,
            allowsOptionalLocks: false
        )
        return NameStatusParser.parse(result.standardOutput)
    }

    /// 某一条 stash 的完整 diff。
    public func stashDiff(at hash: String, in repository: URL) async throws -> Data {
        let result = try await run(
            ["stash", "show", "--include-untracked", "--patch", hash],
            in: repository,
            allowsOptionalLocks: false
        )
        return result.standardOutput
    }

    /// 确认某条 stash 现在排在第几位。
    ///
    /// `git stash drop` 只认 `stash@{N}`，给它 hash 会报 "is not a stash reference"，
    /// 而 N 随时会漂移：删掉中间一条，后面全部前移；用户在终端里 `git stash` 一下，
    /// 全部后移。拿着几秒钟前读到的 N 去 drop，删掉的可能是另一条——
    /// **而 stash 被 drop 之后没有正常途径找回来**。
    ///
    /// 所以执行前用 hash 现查一次位置。查不到（已经被别处删了）就返回 nil，
    /// 由调用方拒绝执行。
    public func stashIndex(of hash: String, in repository: URL) async throws -> Int? {
        try await stashList(in: repository).first { $0.hash == hash }?.index
    }
}

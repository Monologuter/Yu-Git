import Foundation
import GitKit

/// GitKit 的性能基准，对照 PRD 第 5 节与工程规范 §8 的门槛。
///
/// 用法：
///     swift run Benchmark <仓库路径>
///
/// 基准仓库用 `scripts/make-benchmark-repo.py` 生成。

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：swift run Benchmark <仓库路径>\n".utf8))
    exit(2)
}

let repository = URL(fileURLWithPath: arguments[1], isDirectory: true)
let client = try GitClient()

/// 跑若干轮取中位数：单次测量受磁盘缓存与系统调度影响太大。
func measure(_ name: String, threshold: Duration?, rounds: Int = 5, work: () async throws -> Void) async rethrows {
    var samples: [Duration] = []
    let clock = ContinuousClock()

    for _ in 0..<rounds {
        let start = clock.now
        try await work()
        samples.append(clock.now - start)
    }

    samples.sort()
    let median = samples[samples.count / 2]
    let verdict: String
    if let threshold {
        verdict = median <= threshold ? "✅ 达标（门槛 \(threshold)）" : "❌ 超标（门槛 \(threshold)）"
    } else {
        verdict = ""
    }

    print(
        "\(name.padding(toLength: 34, withPad: " ", startingAt: 0)) 中位 \(median)  最快 \(samples[0])  最慢 \(samples[samples.count - 1])  \(verdict)"
    )
}

let commitCount = try await client.commitCount(in: repository, includingAllRefs: true)
print("基准仓库：\(repository.path)")
print("提交总数：\(commitCount)")
print("")

// PRD 第 5 节：5 万 commit 仓库状态 1 秒内出现
try await measure("status（全部未跟踪文件）", threshold: .seconds(1)) {
    _ = try await client.status(of: repository)
}

try await measure("status（不展开未跟踪目录）", threshold: .seconds(1)) {
    _ = try await client.status(of: repository, untrackedFiles: .normal)
}

// PRD 第 5 节：历史首屏 < 500ms
try await measure("log 首屏 200 条", threshold: .milliseconds(500)) {
    _ = try await client.log(in: repository, includingAllRefs: true, maxCount: 200)
}

try await measure("log 首屏 1000 条", threshold: .milliseconds(500)) {
    _ = try await client.log(in: repository, includingAllRefs: true, maxCount: 1000)
}

// 全量解析不是首屏路径，但能看出解析器本身的吞吐
try await measure("log 全量解析", threshold: nil, rounds: 3) {
    _ = try await client.log(in: repository, includingAllRefs: true)
}

try await measure("分支列表", threshold: .milliseconds(200)) {
    _ = try await client.branches(in: repository)
}

try await measure("tag 列表", threshold: .milliseconds(200)) {
    _ = try await client.tags(in: repository)
}

// 三个查询并发，这是界面刷新时的真实路径
try await measure("界面刷新（status+分支+tag+log）", threshold: .seconds(1)) {
    async let status = client.status(of: repository)
    async let branches = client.branches(in: repository)
    async let tags = client.tags(in: repository)
    async let commits = client.log(in: repository, includingAllRefs: true, maxCount: 200)
    _ = try await (status, branches, tags, commits)
}

// 排序方式的代价对比：拓扑序要遍历完整提交图，date 序可以边走边出
try await measure("log 首屏 200 条（拓扑序）", threshold: .milliseconds(500)) {
    _ = try await client.log(
        in: repository, includingAllRefs: true, order: .topological, maxCount: 200)
}

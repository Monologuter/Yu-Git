#!/usr/bin/env python3
"""生成用于性能基准的大仓库。

用 git fast-import 而不是循环调 git commit：后者 5 万次进程启动要跑几十分钟，
前者几秒就能灌完。

用法：
    python3 scripts/make-benchmark-repo.py <提交数> <输出目录>

例：
    python3 scripts/make-benchmark-repo.py 50000 /tmp/yugit-bench
"""

import os
import subprocess
import sys

# 工作区文件数。status 的耗时主要取决于这个，而不是提交数。
FILE_COUNT = 400

# 每隔这么多条提交开一个分支，用来验证 --all 与分支列表的性能。
BRANCH_INTERVAL = 2000


def build_stream(commit_count: int):
    """产出 fast-import 流。"""
    base_time = 1700000000

    for index in range(1, commit_count + 1):
        message = f"第 {index} 条提交\n\n基准仓库的自动生成提交。\n".encode()
        # 每次只改一个文件，模拟真实提交的局部性
        path = f"src/模块{index % FILE_COUNT:03d}/文件.txt"
        content = f"第 {index} 次修改\n".encode()

        yield b"commit refs/heads/main\n"
        yield f"mark :{index}\n".encode()
        yield f"committer 基准测试 <bench@yugit.local> {base_time + index * 60} +0800\n".encode()
        yield f"data {len(message)}\n".encode()
        yield message
        if index > 1:
            yield f"from :{index - 1}\n".encode()
        yield f"M 644 inline {path}\n".encode()
        yield f"data {len(content)}\n".encode()
        yield content
        yield b"\n"

        if index % BRANCH_INTERVAL == 0:
            yield f"reset refs/heads/分支{index // BRANCH_INTERVAL:03d}\n".encode()
            yield f"from :{index}\n\n".encode()

    # 打一批 tag，验证 tag 列表性能
    for index in range(BRANCH_INTERVAL, commit_count + 1, BRANCH_INTERVAL):
        yield f"tag v0.{index // BRANCH_INTERVAL}.0\n".encode()
        yield f"from :{index}\n".encode()
        yield f"tagger 基准测试 <bench@yugit.local> {base_time + index * 60} +0800\n".encode()
        note = f"v0.{index // BRANCH_INTERVAL}.0 版本\n".encode()
        yield f"data {len(note)}\n".encode()
        yield note


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    commit_count = int(sys.argv[1])
    target = os.path.abspath(sys.argv[2])

    if os.path.exists(target):
        print(f"目标已存在，跳过生成：{target}")
        return 0

    os.makedirs(target)
    env = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}

    subprocess.run(["git", "init", "--quiet", "--initial-branch", "main", target], check=True, env=env)

    print(f"正在灌入 {commit_count} 条提交…")
    process = subprocess.Popen(
        ["git", "-C", target, "fast-import", "--quiet"], stdin=subprocess.PIPE, env=env
    )
    assert process.stdin is not None
    for chunk in build_stream(commit_count):
        process.stdin.write(chunk)
    process.stdin.close()
    if process.wait() != 0:
        print("fast-import 失败", file=sys.stderr)
        return 1

    # fast-import 只更新引用，工作区还是空的
    subprocess.run(["git", "-C", target, "checkout", "--quiet", "main"], check=True, env=env)
    subprocess.run(["git", "-C", target, "reset", "--hard", "--quiet", "main"], check=True, env=env)

    total = subprocess.run(
        ["git", "-C", target, "rev-list", "--count", "--all"],
        capture_output=True, text=True, check=True, env=env,
    ).stdout.strip()
    print(f"完成：{target}（{total} 条提交，{FILE_COUNT} 个工作区文件）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

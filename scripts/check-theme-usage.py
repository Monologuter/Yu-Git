#!/usr/bin/env python3
"""检查界面代码里有没有绕过主题层直接写颜色或字号。

`Theme.Colors` 存在的意义是「改一处，四套主题一起对」。只要有一处写死
`.secondary` 或 `Color.orange`，那一处就永远停在系统色上——换主题时它不动，
而周围全变了，看起来像是渲染出了 bug。

这个脚本盯着的就是这件事。它抓不到全部（颜色可以用任意表达式算出来），
但抓得到实际会犯的那几种：直接用系统语义色、直接用 SwiftUI 的具名色、
直接取 NSColor 的语义色。

    ./scripts/check-theme-usage.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "Yugit"
# 主题层自己就是定义色值的地方，不查
EXCLUDED = "DesignSystem"

# 正则 → 该用什么替代
FORBIDDEN = [
    (r"\.foregroundStyle\(\.secondary\)", "Theme.Colors.secondaryText"),
    (r"\.foregroundStyle\(\.tertiary\)", "Theme.Colors.tertiaryText"),
    (r"\.foregroundStyle\(\.primary\)", "Theme.Colors.primaryText"),
    (r"Color\.accentColor", "Theme.Colors.accent"),
    (r"Color\.green\b", "Theme.Colors.success 或 diffAddedText"),
    (r"Color\.red\b", "Theme.Colors.danger 或 diffDeletedText"),
    (r"Color\.orange\b", "Theme.Colors.warning"),
    (r"Color\.purple\b", "Theme.Colors.mergeAccent"),
    (r"Color\.blue\b", "Theme.Colors.accent 或 brand"),
    (r"Color\.gray\b", "Theme.Colors.secondaryText"),
    (r"nsColor:\s*\.underPageBackgroundColor", "Theme.Colors.sunkenBackground"),
    (r"nsColor:\s*\.textBackgroundColor", "Theme.Colors.contentBackground"),
    (r"nsColor:\s*\.controlBackgroundColor", "Theme.Colors.raisedBackground"),
    (r"nsColor:\s*\.labelColor", "Theme.Colors.primaryText"),
    (r"nsColor:\s*\.secondaryLabelColor", "Theme.Colors.secondaryText"),
    (r"nsColor:\s*\.tertiaryLabelColor", "Theme.Colors.tertiaryText"),
    (r"nsColor:\s*\.separatorColor", "Theme.Colors.separator"),
    # 字号同理。设计稿只有九档，而 SwiftUI 的动态字号在 macOS 上
    # 未必是设计稿想要的那个值——`.title3` 在 iOS 是 20pt，在 macOS 是 15pt。
    (r"\.font\(\.caption2?\b", "Theme.Font.secondary 或 caption"),
    (r"\.font\(\.callout\b", "Theme.Font.callout"),
    (r"\.font\(\.body\b", "Theme.Font.body"),
    (r"\.font\(\.headline\b", "Theme.Font.title"),
    (r"\.font\(\.subheadline\b", "Theme.Font.secondary"),
    (r"\.font\(\.title[23]?\b", "Theme.Font.title 或 sheetTitle"),
    (r"\.font\(\.footnote\b", "Theme.Font.caption"),
    (r"design:\s*\.monospaced", "Theme.Font.mono"),
]


def main() -> int:
    problems: list[str] = []
    scanned = 0

    for path in sorted(UI.rglob("*.swift")):
        if EXCLUDED in str(path):
            continue
        scanned += 1
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            # 注释里提到某个颜色名是在解释为什么不用它，不算违规
            if line.strip().startswith("//") or line.strip().startswith("///"):
                continue
            for pattern, replacement in FORBIDDEN:
                if re.search(pattern, line):
                    relative = path.relative_to(ROOT)
                    problems.append(f"{relative}:{number} → 改用 {replacement}\n    {line.strip()}")

    print(f"扫了 {scanned} 个界面文件")
    if problems:
        print()
        for problem in problems:
            print(f"  ✗ {problem}")
        print(f"\n{len(problems)} 处绕过了主题层")
        return 1

    print("✓ 界面颜色与字号全部走主题层")
    return 0


if __name__ == "__main__":
    sys.exit(main())

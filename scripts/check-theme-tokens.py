#!/usr/bin/env python3
"""核对 Swift 里的主题色值与设计稿的 CSS token 是否一致。

设计系统产出的是 CSS，代码里是 Swift 字面量，两边靠人手工抄。
四套主题 × 浅深两份 × 三十来个 token，一共三百多个十六进制数——
抄错一个不会编译失败，也不会有测试变红，只会在某个主题的某个角落
出现一处谁也说不清为什么的颜色。这个脚本就是那道防线。

设计稿更新了 token 之后跑一次；不一致会列出每一处并以非零码退出。

    ./scripts/check-theme-tokens.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS_DEFAULT = ROOT / "design/驭Git/tokens/colors.css"
CSS_THEMES = ROOT / "design/驭Git/tokens/themes.css"
SWIFT_DEFAULT = ROOT / "Yugit/DesignSystem/ThemePalette.swift"
SWIFT_THEMES = ROOT / "Yugit/DesignSystem/Palettes.swift"

# CSS 变量名 → ThemePalette 的属性名。
# 没列进来的（--accent 一族、--surface-press、
# --brand-wash-strong）是刻意的：强调色跟随系统不落死值，其余几个
# 还没有对应的 token，等用到时再加。
TOKENS = {
    "brand": "brand",
    "brand-hover": "brandHover",
    "brand-wash": "brandWash",
    "brand-on": "onBrand",
    "surface-app": "contentBackground",
    "surface-sunken": "sunkenBackground",
    "surface-raised": "raisedBackground",
    "surface-hover": "hoverBackground",
    "fill-quaternary": "fillQuaternary",
    "ink-1": "primaryText",
    "ink-2": "secondaryText",
    "ink-3": "tertiaryText",
    "ink-4": "decorativeText",
    "hairline": "separator",
    "hairline-strong": "separatorStrong",
    "warn": "warning",
    "warn-wash": "warningWash",
    "ok": "success",
    "merge": "mergeAccent",
    "danger": "danger",
    "diff-add-fg": "diffAddedText",
    "diff-del-fg": "diffDeletedText",
    "diff-add-row": "diffAddedLine",
    "diff-del-row": "diffDeletedLine",
    "diff-add-word": "diffAddedWord",
    "diff-del-word": "diffDeletedWord",
    "syn-keyword": "syntaxKeyword",
    "syn-string": "syntaxString",
    "syn-comment": "syntaxComment",
    "syn-number": "syntaxNumber",
    "syn-type": "syntaxType",
}

# Swift 结构体 → (CSS 浅色选择器, CSS 深色选择器)
THEMES = [
    ("SystemTheme", ":root", 'dark'),
    ("InkTheme", "mo", "mo-dark"),
    ("DaylightTheme", "zhou", "zhou-dark"),
    ("SpectrumTheme", "pu", "pu-dark"),
]

HEX = r"#[0-9A-Fa-f]{6}"


def css_groups() -> dict[str, dict[str, str]]:
    groups: dict[str, dict[str, str]] = {}
    default = CSS_DEFAULT.read_text(encoding="utf-8")

    root = re.search(r":root\s*\{(.*?)\n\}", default, re.S)
    groups[":root"] = dict(re.findall(rf"--([\w-]+):\s*({HEX})", root.group(1)))

    for text in (default, CSS_THEMES.read_text(encoding="utf-8")):
        for match in re.finditer(r'\[data-theme="([\w-]+)"\]\s*\{(.*?)\n\}', text, re.S):
            groups[match.group(1)] = dict(
                re.findall(rf"--([\w-]+):\s*({HEX})", match.group(2))
            )
    return groups


def swift_values(struct: str) -> tuple[dict[str, tuple[str, str]], list[tuple[str, str, str]]]:
    """返回 (属性名 → 浅深两个值, 轨道列表)。"""
    source = (SWIFT_DEFAULT if struct == "SystemTheme" else SWIFT_THEMES).read_text(
        encoding="utf-8"
    )
    body = re.search(rf"struct {struct}: ThemePalette \{{(.*?)\n\}}\n", source, re.S)
    if body is None:
        raise SystemExit(f"在源码里找不到 {struct}")
    body = body.group(1)

    pair = r"\.theme\(light: (0x[0-9A-Fa-f_]+), dark: (0x[0-9A-Fa-f_]+)\)"
    props = {
        name: (light, dark)
        for name, light, dark in re.findall(rf"var (\w+): Color \{{ {pair} \}}", body)
    }
    lanes = re.findall(rf"{pair},\s+// (\d)", body)
    return props, lanes


def normalize(value: str) -> str:
    return value.upper().replace("_", "").replace("0X", "").lstrip("#")


def main() -> int:
    groups = css_groups()
    problems: list[str] = []

    for struct, light_key, dark_key in THEMES:
        props, lanes = swift_values(struct)
        checked = 0

        for css_name, prop in TOKENS.items():
            if prop not in props:
                problems.append(f"{struct}.{prop} 在 Swift 里找不到")
                continue
            for group, index in ((light_key, 0), (dark_key, 1)):
                want = normalize(groups[group][css_name])
                got = normalize(props[prop][index])
                checked += 1
                if want != got:
                    problems.append(
                        f"{struct}.{prop} [{group} --{css_name}] css={want} swift={got}"
                    )

        if len(lanes) != 8:
            problems.append(f"{struct} 只有 {len(lanes)} 条轨道，应为 8 条")
        for light, dark, number in lanes:
            for group, value in ((light_key, light), (dark_key, dark)):
                want = normalize(groups[group][f"lane-{number}"])
                got = normalize(value)
                checked += 1
                if want != got:
                    problems.append(f"{struct} lane-{number} [{group}] css={want} swift={got}")

        print(f"{struct:16} 核对 {checked} 个值")

    if problems:
        print()
        for problem in problems:
            print(f"  ✗ {problem}")
        print(f"\n{len(problems)} 处与设计稿不一致")
        return 1

    print("\n✓ 与设计稿一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())

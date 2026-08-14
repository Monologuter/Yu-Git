---
name: yugit-design
description: Use this skill to generate well-branded interfaces and assets for 驭Git (Yugit), a Chinese-language macOS-native Git client, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for protoyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.
If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.
If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

Start with `readme.md` (product context, content rules, visual foundations, iconography, component index) and `guidelines/tokens-table.md` (every色值 and size in text form: 名称 | 浅色 hex | 深色 hex | 用途). The UI kits in `ui_kits/` show what a finished screen looks like; `components/*/*.prompt.md` says when to use each component.

Three rules that break the design if ignored: 红与绿只属于 diff；纯蓝是系统强调色，不是品牌色；品牌色是靛 `#4A3D8B`（深色 `#938BDA`），且不进分支图 —— HEAD 外环用 `--ink-1`。

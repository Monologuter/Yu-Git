/* @ds-bundle: {"format":4,"namespace":"Git_c7d67c","components":[{"name":"CountPill","sourcePath":"components/badges/CountPill.jsx"},{"name":"RefBadge","sourcePath":"components/badges/RefBadge.jsx"},{"name":"StatusLetter","sourcePath":"components/badges/StatusLetter.jsx"},{"name":"TrackingBadge","sourcePath":"components/badges/TrackingBadge.jsx"},{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"Checkbox","sourcePath":"components/controls/Checkbox.jsx"},{"name":"CopyButton","sourcePath":"components/controls/CopyButton.jsx"},{"name":"FilterField","sourcePath":"components/controls/FilterField.jsx"},{"name":"SegmentedControl","sourcePath":"components/controls/SegmentedControl.jsx"},{"name":"ToolbarButton","sourcePath":"components/controls/ToolbarButton.jsx"},{"name":"Icon","sourcePath":"components/core/Icon.jsx"},{"name":"DiffLine","sourcePath":"components/diff/DiffLine.jsx"},{"name":"HunkHeader","sourcePath":"components/diff/HunkHeader.jsx"},{"name":"SelectionBar","sourcePath":"components/diff/SelectionBar.jsx"},{"name":"Banner","sourcePath":"components/feedback/Banner.jsx"},{"name":"EmptyState","sourcePath":"components/feedback/EmptyState.jsx"},{"name":"ExplanationPanel","sourcePath":"components/feedback/ExplanationPanel.jsx"},{"name":"HazardDialog","sourcePath":"components/feedback/HazardDialog.jsx"},{"name":"TransferIndicator","sourcePath":"components/feedback/TransferIndicator.jsx"},{"name":"GEOMETRY","sourcePath":"components/graph/LaneGraph.jsx"},{"name":"LANE_COUNT","sourcePath":"components/graph/LaneGraph.jsx"},{"name":"LaneGraph","sourcePath":"components/graph/LaneGraph.jsx"},{"name":"BranchRow","sourcePath":"components/rows/BranchRow.jsx"},{"name":"CommitRow","sourcePath":"components/rows/CommitRow.jsx"},{"name":"DayGroupRow","sourcePath":"components/rows/DayGroupRow.jsx"},{"name":"DirectoryRow","sourcePath":"components/rows/DirectoryRow.jsx"},{"name":"FileRow","sourcePath":"components/rows/FileRow.jsx"},{"name":"SectionHeader","sourcePath":"components/rows/SectionHeader.jsx"},{"name":"TagRow","sourcePath":"components/rows/TagRow.jsx"}],"sourceHashes":{"components/badges/CountPill.jsx":"6cb5cc555763","components/badges/RefBadge.jsx":"79fe02f2b497","components/badges/StatusLetter.jsx":"a94c9ed3e2f3","components/badges/TrackingBadge.jsx":"831a7776f333","components/controls/Button.jsx":"aa96b4a3c6ac","components/controls/Checkbox.jsx":"f32114d80576","components/controls/CopyButton.jsx":"ae6687762b5c","components/controls/FilterField.jsx":"8c1cb2b435a2","components/controls/SegmentedControl.jsx":"eaa76b01e7e3","components/controls/ToolbarButton.jsx":"d5093b4be55e","components/core/Icon.jsx":"0d4321f587b1","components/diff/DiffLine.jsx":"152c2ec51cd8","components/diff/HunkHeader.jsx":"ec7c578c9199","components/diff/SelectionBar.jsx":"3334771edb7e","components/feedback/Banner.jsx":"5e9a3e1fa8f6","components/feedback/EmptyState.jsx":"b0b0106838ff","components/feedback/ExplanationPanel.jsx":"22f5b99c32da","components/feedback/HazardDialog.jsx":"3a9de28924be","components/feedback/TransferIndicator.jsx":"c5a541ab0fa2","components/graph/LaneGraph.jsx":"da563339e70d","components/rows/BranchRow.jsx":"48672a2cb6b4","components/rows/CommitRow.jsx":"0d99a89fda08","components/rows/DayGroupRow.jsx":"0055791f2b02","components/rows/DirectoryRow.jsx":"dac4314e2d46","components/rows/FileRow.jsx":"bd7ee0fdac3d","components/rows/SectionHeader.jsx":"dbabf9d8b587","components/rows/TagRow.jsx":"efa6e216345b","ui_kits/first-run/Tour.jsx":"cc4fb055fe1d","ui_kits/first-run/Welcome.jsx":"afc1774b81d6","ui_kits/mac-app/ChangesPane.jsx":"714117b1f98d","ui_kits/mac-app/CommandPalette.jsx":"69f26f4a972e","ui_kits/mac-app/DetailPane.jsx":"cf3538c12eda","ui_kits/mac-app/HistoryPane.jsx":"9b6dfa941e66","ui_kits/mac-app/Sidebar.jsx":"6f421280ccf7","ui_kits/mac-app/Timeline.jsx":"31779278730a","ui_kits/mac-app/Toolbar.jsx":"1a2ef9ec397d","ui_kits/mac-app/data.js":"99f843813b59"},"inlinedExternals":[],"unexposedExports":[{"name":"graphWidth","sourcePath":"components/graph/LaneGraph.jsx"},{"name":"laneColor","sourcePath":"components/graph/LaneGraph.jsx"}]} */

(() => {

const __ds_ns = (window.Git_c7d67c = window.Git_c7d67c || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/badges/CountPill.jsx
try { (() => {
/** 计数胶囊。跟在标题后面说明「有几个」，不参与点击。 */
function CountPill({
  children,
  tone = 'neutral',
  style
}) {
  const warn = tone === 'warn';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      minWidth: 16,
      padding: '1px 5px',
      borderRadius: 'var(--radius-capsule)',
      font: 'var(--type-secondary)',
      fontVariantNumeric: 'tabular-nums',
      background: warn ? 'var(--warn-wash)' : 'var(--fill-quaternary)',
      color: warn ? 'var(--warn)' : 'var(--ink-2)',
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { CountPill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/badges/CountPill.jsx", error: String((e && e.message) || e) }); }

// components/badges/RefBadge.jsx
try { (() => {
/**
 * commit 上的分支 / tag 徽章。
 * HEAD 不单独画 —— 它总和它指向的分支一起出现，单独一个徽章只是噪音。
 */
const TONE = {
  local: 'var(--brand)',
  remote: 'var(--ink-2)',
  tag: 'var(--warn)'
};
function RefBadge({
  kind = 'local',
  children,
  emphasized = false,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      maxWidth: 170,
      padding: '1px 5px',
      borderRadius: 'var(--radius-capsule)',
      font: 'var(--type-caption)',
      color: emphasized ? 'var(--selection-fg)' : TONE[kind],
      background: emphasized ? 'color-mix(in srgb, var(--selection-fg) 22%, transparent)' : 'color-mix(in srgb, ' + TONE[kind] + ' 15%, transparent)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { RefBadge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/badges/RefBadge.jsx", error: String((e && e.message) || e) }); }

// components/badges/StatusLetter.jsx
try { (() => {
/**
 * 文件状态字母。等宽 + 固定 14px 宽，好让后面的路径左边界对齐成一列；
 * 不固定的话 A/M/D 宽度不同，整列会呈锯齿状。
 * 状态永远同时由字母和颜色表达 —— 只靠颜色的话色盲用户什么都读不到。
 */
const MAP = {
  added: {
    letter: 'A',
    color: 'var(--ok)',
    name: '新增'
  },
  modified: {
    letter: 'M',
    color: 'var(--accent)',
    name: '修改'
  },
  deleted: {
    letter: 'D',
    color: 'var(--danger)',
    name: '删除'
  },
  renamed: {
    letter: 'R',
    color: 'var(--merge)',
    name: '改名'
  },
  copied: {
    letter: 'C',
    color: 'var(--merge)',
    name: '复制'
  },
  untracked: {
    letter: '?',
    color: 'var(--ink-2)',
    name: '未跟踪'
  },
  unmerged: {
    letter: '!',
    color: 'var(--warn)',
    name: '有冲突'
  },
  ignored: {
    letter: '·',
    color: 'var(--ink-4)',
    name: '已忽略'
  },
  typechange: {
    letter: 'T',
    color: 'var(--accent)',
    name: '类型变化'
  }
};
function StatusLetter({
  status,
  emphasized = false,
  style
}) {
  const entry = MAP[status] || MAP.modified;
  return /*#__PURE__*/React.createElement("span", {
    title: entry.name,
    style: {
      display: 'inline-block',
      width: 14,
      textAlign: 'center',
      flex: '0 0 auto',
      font: 'var(--type-mono)',
      color: emphasized ? 'var(--selection-fg)' : entry.color,
      ...style
    }
  }, entry.letter);
}
Object.assign(__ds_scope, { StatusLetter });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/badges/StatusLetter.jsx", error: String((e && e.message) || e) }); }

// components/controls/SegmentedControl.jsx
try { (() => {
/**
 * 分段控件。中栏顶部的「变更 N｜历史」就是它。
 * 选中段用强调色填充 + 白字，跟系统 .pickerStyle(.segmented) 一致。
 */
function SegmentedControl({
  items,
  value,
  onChange,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: 'flex',
      gap: 2,
      padding: 2,
      borderRadius: 'var(--radius-medium)',
      background: 'var(--fill-quaternary)',
      border: '1px solid var(--hairline)',
      ...style
    }
  }, items.map(item => {
    const selected = item.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: item.value,
      type: "button",
      role: "tab",
      "aria-selected": selected,
      onClick: () => onChange && onChange(item.value),
      title: item.title,
      style: {
        flex: 1,
        height: 20,
        border: 'none',
        borderRadius: 'var(--radius-small)',
        font: 'var(--type-body)',
        fontWeight: selected ? 'var(--weight-medium)' : 'var(--weight-regular)',
        background: selected ? 'var(--accent)' : 'transparent',
        color: selected ? 'var(--text-on-accent)' : 'var(--text-body)',
        cursor: 'default',
        whiteSpace: 'nowrap',
        transition: 'background var(--dur-fast) var(--ease-standard)'
      }
    }, item.label);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// components/core/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * 一个 SF Symbol 的位置。name 就是符号名，和 Swift 侧 Image(systemName:) 一字不差。
 *
 * 这里不画替身图形，也不带任何图片资源。SF Symbols 不是 Unicode 字符，是 SF 字体
 * 私有区里的字形，既不能随设计系统分发，网页里也拿不到；画一套描边 SVG 去凑，
 * 会同时丢掉跟随字重、跟随字号、跟随辅助功能加粗、自动适配深浅这四件事 ——
 * 而那四件事正是选 SF Symbols 的理由。
 *
 * 所以预览端渲染一个与符号同尺寸的占位框：间距、对齐、基线、行内节奏都和真机一致，
 * 只有字形本身留空。符号名进 data-sf-symbol 与 title，验收和交接都读它。
 * 框是虚线的 —— 实线方框在文件行里会被读成 Checkbox，而那是一个真实存在的控件。
 *
 * 想在 Mac 上看到真符号：页面里塞一张字形表就行 ——
 *   window.YUGIT_SYMBOL_GLYPHS = { 'arrow.triangle.branch': <这里粘字形>, … }
 * （字形从 SF Symbols.app 的「拷贝符号」拿）。有表的用 SF Pro 直接画，没有的照旧占位。
 */
function Icon({
  name,
  size = 14,
  color = 'currentColor',
  title,
  style,
  ...rest
}) {
  const glyphs = typeof window !== 'undefined' && window.YUGIT_SYMBOL_GLYPHS || {};
  const glyph = glyphs[name];
  return /*#__PURE__*/React.createElement("span", _extends({
    "data-sf-symbol": name,
    title: title || name,
    "aria-hidden": title ? undefined : true,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: size,
      height: size,
      flex: '0 0 auto',
      color,
      ...style
    }
  }, rest), glyph ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: '"SF Pro Text", "SF Pro", -apple-system, system-ui',
      fontSize: size,
      lineHeight: 1
    }
  }, glyph) : /*#__PURE__*/React.createElement("span", {
    style: {
      width: '76%',
      height: '76%',
      boxSizing: 'border-box',
      border: '1px dashed currentColor',
      borderRadius: Math.max(2, Math.round(size * 0.18)),
      opacity: 0.42
    }
  }));
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Icon.jsx", error: String((e && e.message) || e) }); }

// components/badges/TrackingBadge.jsx
try { (() => {
/** 分支的 ahead / behind 指示。upstream 被删了单独警示 —— 那会让 push 直接失败。 */
function TrackingBadge({
  ahead = 0,
  behind = 0,
  gone = false,
  emphasized = false,
  style
}) {
  if (gone) {
    return /*#__PURE__*/React.createElement("span", {
      title: "upstream \u5DF2\u5728\u8FDC\u7A0B\u88AB\u5220\u9664",
      style: {
        display: 'inline-flex',
        color: emphasized ? 'var(--selection-fg)' : 'var(--warn)',
        ...style
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: "exclamationmark.triangle",
      size: 11
    }));
  }
  if (!ahead && !behind) return null;
  return /*#__PURE__*/React.createElement("span", {
    title: '领先 ' + ahead + '，落后 ' + behind,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 5,
      font: 'var(--type-caption)',
      color: emphasized ? 'var(--selection-fg)' : 'var(--ink-2)',
      fontVariantNumeric: 'tabular-nums',
      ...style
    }
  }, ahead ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow.up",
    size: 9
  }), ahead) : null, behind ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow.down",
    size: 9
  }), behind) : null);
}
Object.assign(__ds_scope, { TrackingBadge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/badges/TrackingBadge.jsx", error: String((e && e.message) || e) }); }

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * 按钮。对应 SwiftUI 的 .bordered / .borderless / .plain 三种 buttonStyle
 * 加上 keyboardShortcut(.defaultAction) 那一档（variant="default"）。
 * 高度按 controlSize 走 20 / 24 / 32，不是随手取的：和系统控件同高才能排在一行里。
 */
const HEIGHT = {
  small: 20,
  regular: 24,
  large: 32
};
const FONT = {
  small: 'var(--text-size-secondary)',
  regular: 'var(--text-size-body)',
  large: 'var(--text-size-body)'
};
const PAD = {
  small: 8,
  regular: 10,
  large: 14
};
function Button({
  children,
  variant = 'bordered',
  size = 'regular',
  icon,
  disabled = false,
  fullWidth = false,
  onClick,
  title,
  style,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 'var(--space-tight)',
    height: HEIGHT[size],
    padding: '0 ' + PAD[size] + 'px',
    font: 'var(--type-body)',
    fontSize: FONT[size],
    fontWeight: 'var(--weight-regular)',
    borderRadius: 'var(--radius-medium)',
    border: '1px solid transparent',
    background: 'transparent',
    color: 'var(--text-body)',
    cursor: disabled ? 'default' : 'default',
    opacity: disabled ? 0.4 : 1,
    whiteSpace: 'nowrap',
    width: fullWidth ? '100%' : undefined,
    transition: 'background var(--dur-fast) var(--ease-standard)',
    WebkitFontSmoothing: 'antialiased'
  };
  const skins = {
    bordered: {
      background: pressed ? 'var(--surface-press)' : 'var(--surface-app)',
      borderColor: 'var(--border-control)',
      boxShadow: '0 0.5px 1px rgba(0,0,0,0.04)'
    },
    default: {
      background: pressed ? 'var(--brand-hover)' : 'var(--accent)',
      borderColor: 'transparent',
      color: 'var(--text-on-accent)',
      fontWeight: 'var(--weight-medium)'
    },
    borderless: {
      background: pressed ? 'var(--surface-press)' : 'transparent',
      color: 'var(--accent)',
      padding: '0 ' + (PAD[size] - 6) + 'px'
    },
    destructive: {
      background: pressed ? 'var(--surface-press)' : 'transparent',
      color: 'var(--danger)',
      padding: '0 ' + (PAD[size] - 6) + 'px'
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    title: title,
    disabled: disabled,
    onClick: disabled ? undefined : onClick,
    onMouseDown: () => setPressed(true),
    onMouseUp: () => setPressed(false),
    onMouseLeave: () => setPressed(false),
    style: {
      ...base,
      ...skins[variant],
      ...style
    }
  }, rest), icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: size === 'small' ? 11 : 13
  }) : null, children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/Checkbox.jsx
try { (() => {
/** 复选框。对应 Toggle(.checkbox)，标签 11pt。 */
function Checkbox({
  checked,
  onChange,
  label,
  disabled = false,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      font: 'var(--type-secondary)',
      color: 'var(--text-body)',
      opacity: disabled ? 0.4 : 1,
      cursor: 'default',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: 13,
      height: 13,
      borderRadius: 3,
      background: checked ? 'var(--accent)' : 'var(--surface-app)',
      border: '1px solid ' + (checked ? 'transparent' : 'var(--border-control)'),
      boxShadow: checked ? 'none' : '0 0.5px 1px rgba(0,0,0,0.04)',
      color: 'var(--text-on-accent)'
    }
  }, checked ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "checkmark",
    size: 9
  }) : null), label);
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/controls/CopyButton.jsx
try { (() => {
/**
 * 复制按钮，点完给 1.5 秒的「已复制」反馈。
 * 没有反馈的复制按钮最让人犯嘀咕：什么都没发生，用户会再点两下。
 */
function CopyButton({
  text,
  title = '复制',
  onCopy,
  style
}) {
  const [done, setDone] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: title,
    onClick: () => {
      if (onCopy) onCopy(text);else if (navigator.clipboard) navigator.clipboard.writeText(text);
      setDone(true);
      window.setTimeout(() => setDone(false), 1500);
    },
    style: {
      display: 'inline-flex',
      border: 'none',
      background: 'transparent',
      padding: 2,
      color: done ? 'var(--ok)' : 'var(--ink-2)',
      cursor: 'default',
      transition: 'color var(--dur-medium) var(--ease-standard)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: done ? 'check' : 'copy',
    size: 11
  }));
}
Object.assign(__ds_scope, { CopyButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/CopyButton.jsx", error: String((e && e.message) || e) }); }

// components/controls/FilterField.jsx
try { (() => {
/**
 * 过滤框。放在它所影响的那一列的顶部 —— 位置本身说明了它管什么范围，
 * 这也是不用 .searchable 的原因（那会把框放进全窗口共用的工具栏）。
 */
function FilterField({
  value,
  onChange,
  placeholder,
  autoFocus = false,
  style
}) {
  const [focused, setFocused] = React.useState(false);
  const ref = React.useRef(null);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      flex: 1,
      minWidth: 0,
      padding: '5px var(--space-regular)',
      borderRadius: 'var(--radius-medium)',
      background: 'var(--fill-quaternary)',
      boxShadow: focused ? 'inset 0 0 0 2px var(--border-focus)' : 'none',
      transition: 'box-shadow var(--dur-fast) var(--ease-standard)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "line.3.horizontal.decrease",
    size: 11,
    color: "var(--ink-2)"
  }), /*#__PURE__*/React.createElement("input", {
    ref: ref,
    value: value,
    placeholder: placeholder,
    autoFocus: autoFocus,
    onChange: e => onChange && onChange(e.target.value),
    onFocus: () => setFocused(true),
    onBlur: () => setFocused(false),
    style: {
      flex: 1,
      minWidth: 0,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      font: 'var(--type-secondary)',
      color: 'var(--text-body)'
    }
  }), value ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: "\u6E05\u7A7A",
    onClick: () => {
      onChange && onChange('');
      if (ref.current) ref.current.focus();
    },
    style: {
      display: 'flex',
      border: 'none',
      background: 'transparent',
      padding: 0,
      color: 'var(--ink-4)',
      cursor: 'default'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "xmark.circle",
    size: 11
  })) : null);
}
Object.assign(__ds_scope, { FilterField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/FilterField.jsx", error: String((e && e.message) || e) }); }

// components/controls/ToolbarButton.jsx
try { (() => {
/**
 * 窗口工具栏上的图标按钮。
 * 工具栏可用宽度是被三栏分掉的剩余空间，比看上去窄得多 ——
 * 所以这里只放图标，文字进 title。
 */
function ToolbarButton({
  icon,
  title,
  disabled = false,
  active = false,
  onClick,
  badge,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: title,
    disabled: disabled,
    onClick: disabled ? undefined : onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: 'relative',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: 28,
      height: 24,
      border: 'none',
      borderRadius: 'var(--radius-small) ',
      background: active ? 'var(--surface-press)' : hover && !disabled ? 'var(--surface-hover)' : 'transparent',
      color: active ? 'var(--text-body)' : 'var(--ink-2)',
      opacity: disabled ? 0.35 : 1,
      cursor: 'default',
      padding: 0,
      transition: 'background var(--dur-fast) var(--ease-standard)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 16
  }), badge ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 1,
      right: 1,
      width: 6,
      height: 6,
      borderRadius: '50%',
      background: 'var(--warn)'
    }
  }) : null);
}
Object.assign(__ds_scope, { ToolbarButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/ToolbarButton.jsx", error: String((e && e.message) || e) }); }

// components/diff/DiffLine.jsx
try { (() => {
/**
 * diff 里的一行：双列行号 + 标记 + 内容。
 *
 * 语法高亮和行内变化底色是两个正交的维度，叠在一起而不是二选一：
 * 语法色管「这是什么」，行内底色管「这里改了」。只留一个的话，
 * 要么看不出改在哪，要么代码读起来费劲。
 * 选中时两者都关掉 —— 此刻用户关心的是「我选了哪些行」。
 */
const SYNTAX = {
  keyword: 'var(--syn-keyword)',
  string: 'var(--syn-string)',
  comment: 'var(--syn-comment)',
  number: 'var(--syn-number)',
  type: 'var(--syn-type)',
  plain: 'var(--syn-plain)'
};
function DiffLine({
  kind = 'context',
  oldNumber,
  newNumber,
  text,
  segments,
  selected = false,
  gutterWidth = 34,
  wrap = false,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  const selectable = kind !== 'context';
  const rowBackground = selected ? 'color-mix(in srgb, var(--accent) 22%, transparent)' : hover && selectable ? 'var(--surface-hover)' : kind === 'addition' ? 'var(--diff-add-row)' : kind === 'deletion' ? 'var(--diff-del-row)' : 'transparent';
  const marker = kind === 'addition' ? '+' : kind === 'deletion' ? '−' : ' ';
  const markerColor = kind === 'addition' ? 'var(--diff-add-fg)' : kind === 'deletion' ? 'var(--diff-del-fg)' : 'var(--ink-3)';
  const wordBackground = kind === 'addition' ? 'var(--diff-add-word)' : 'var(--diff-del-word)';
  const number = value => /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      width: gutterWidth,
      paddingRight: 6,
      textAlign: 'right',
      font: 'var(--type-mono)',
      color: 'var(--ink-3)',
      fontVariantNumeric: 'tabular-nums',
      userSelect: 'none'
    }
  }, value == null ? '' : value);
  return /*#__PURE__*/React.createElement("div", {
    onClick: selectable && onClick ? onClick : undefined,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    title: selectable ? '点击选中此行，按住 Shift 可连选' : undefined,
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: wrap ? 'flex-start' : 'center',
      minHeight: 18,
      padding: '1px 0',
      background: rowBackground,
      ...style
    }
  }, selected ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 0,
      top: 0,
      bottom: 0,
      width: 3,
      background: 'var(--accent)'
    }
  }) : null, number(oldNumber), number(newNumber), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      width: 14,
      textAlign: 'center',
      font: 'var(--type-mono)',
      color: markerColor,
      userSelect: 'none'
    }
  }, marker), /*#__PURE__*/React.createElement("code", {
    style: {
      font: 'var(--type-mono)',
      color: 'var(--syn-plain)',
      whiteSpace: wrap ? 'pre-wrap' : 'pre',
      overflowWrap: wrap ? 'anywhere' : 'normal',
      minWidth: 0
    }
  }, segments ? segments.map((segment, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      color: selected ? 'inherit' : SYNTAX[segment.syn || 'plain'],
      background: segment.changed && !selected ? wordBackground : 'transparent'
    }
  }, segment.text)) : text));
}
Object.assign(__ds_scope, { DiffLine });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/diff/DiffLine.jsx", error: String((e && e.message) || e) }); }

// components/diff/HunkHeader.jsx
try { (() => {
/** hunk 头，兼作「暂存此块」的入口。悬停才显示按钮，避免密集的按钮干扰阅读。 */
function HunkHeader({
  header,
  action,
  sticky = true,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)',
      padding: '4px var(--space-loose)',
      background: 'var(--surface-sunken)',
      position: sticky ? 'sticky' : 'static',
      top: 0,
      zIndex: 1,
      font: 'var(--type-mono)',
      color: 'var(--ink-2)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, header), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      visibility: hover && action ? 'visible' : 'hidden'
    }
  }, action));
}
Object.assign(__ds_scope, { HunkHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/diff/HunkHeader.jsx", error: String((e && e.message) || e) }); }

// components/diff/SelectionBar.jsx
try { (() => {
/** 有行被选中时出现的操作条。半透明材质，压在 diff 顶部。 */
function SelectionBar({
  count,
  primaryLabel = '暂存选中的行',
  onApply,
  onClear,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-loose)',
      padding: '6px var(--space-loose)',
      background: 'var(--surface-sidebar)',
      backdropFilter: 'var(--blur-overlay)',
      WebkitBackdropFilter: 'var(--blur-overlay)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-callout)',
      color: 'var(--text-body)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", null, "\u5DF2\u9009 ", count, " \u884C"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClear,
    style: {
      border: 'none',
      background: 'transparent',
      font: 'var(--type-callout)',
      color: 'var(--accent)',
      cursor: 'default'
    }
  }, "\u6E05\u9664\u9009\u62E9"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onApply,
    style: {
      height: 22,
      padding: '0 10px',
      border: 'none',
      borderRadius: 'var(--radius-medium)',
      background: 'var(--accent)',
      color: 'var(--text-on-accent)',
      font: 'var(--type-callout)',
      fontWeight: 'var(--weight-medium)',
      cursor: 'default'
    }
  }, primaryLabel));
}
Object.assign(__ds_scope, { SelectionBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/diff/SelectionBar.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Banner.jsx
try { (() => {
/**
 * 横幅。卡在 rebase 半途是 Git 里最容易让人懵的状态：
 * 命令行下只有一段 hint，关掉终端就没了。所以这条横幅只要状态还在就一直挂着，
 * 并且把出路直接做成按钮。它横跨三栏，切到哪一栏都看得见。
 */
const TONES = {
  warn: {
    fg: 'var(--warn)',
    bg: 'var(--warn-wash)',
    icon: 'exclamationmark.triangle'
  },
  danger: {
    fg: 'var(--danger)',
    bg: 'var(--danger-wash)',
    icon: 'exclamationmark.triangle'
  },
  info: {
    fg: 'var(--brand)',
    bg: 'var(--brand-wash)',
    icon: 'info.circle'
  },
  ok: {
    fg: 'var(--ok)',
    bg: 'var(--ok-wash)',
    icon: 'checkmark.circle'
  }
};
function Banner({
  tone = 'warn',
  headline,
  detail,
  actions,
  footnote,
  style
}) {
  const skin = TONES[tone];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)',
      padding: 'var(--space-regular) var(--space-regular)',
      background: skin.bg,
      borderBottom: '1px solid var(--hairline)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: skin.icon,
    size: 14,
    color: skin.fg
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      fontWeight: 'var(--weight-medium)',
      color: 'var(--text-body)'
    }
  }, headline), detail ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)'
    }
  }, detail) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), actions ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 'var(--space-regular)',
      flex: '0 0 auto'
    }
  }, actions) : null), footnote ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "shield",
    size: 10
  }), footnote) : null);
}
Object.assign(__ds_scope, { Banner });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Banner.jsx", error: String((e && e.message) || e) }); }

// components/feedback/EmptyState.jsx
try { (() => {
/**
 * 空状态。
 *
 * 系统的 ContentUnavailableView 一上来就是一个灰色大图标 + 灰字，
 * 每个空状态长得一样，也不告诉人下一步做什么。这里做三件事：
 * 图标放进品牌色的圆底（一屏之内唯一的色块，认得出是驭Git）、
 * 标题说清「现在是什么情况」、说明句给出「下一步做什么」。
 */
function EmptyState({
  icon = 'checkmark.circle',
  title,
  description,
  action,
  tone = 'brand',
  compact = false,
  style
}) {
  const fg = tone === 'warn' ? 'var(--warn)' : 'var(--brand)';
  const bg = tone === 'warn' ? 'var(--warn-wash)' : 'var(--brand-wash)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: compact ? 'var(--space-regular)' : 'var(--space-loose)',
      padding: compact ? 'var(--space-section)' : 'var(--space-major)',
      textAlign: 'center',
      height: '100%',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: compact ? 36 : 48,
      height: compact ? 36 : 48,
      borderRadius: '50%',
      background: bg,
      color: fg
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: compact ? 18 : 22
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-tight)',
      maxWidth: 260
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-title)',
      color: 'var(--text-body)'
    }
  }, title), description ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--ink-2)',
      textWrap: 'pretty'
    }
  }, description) : null), action);
}
Object.assign(__ds_scope, { EmptyState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/EmptyState.jsx", error: String((e && e.message) || e) }); }

// components/feedback/ExplanationPanel.jsx
try { (() => {
/**
 * 「用中文讲讲这是什么」面板。
 * 默认收起，展开一次才发一次请求 —— AI 铁律：只有用户主动要，才把内容发出去。
 * 没配 AI 时整块不出现，界面上不留任何 AI 痕迹。
 */
function ExplanationPanel({
  title,
  text,
  loading = false,
  expanded,
  onToggle,
  error,
  style
}) {
  const [inner, setInner] = React.useState(false);
  const open = expanded === undefined ? inner : expanded;
  const toggle = () => onToggle ? onToggle(!open) : setInner(!open);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)',
      padding: 'var(--space-loose)',
      borderRadius: 8,
      background: 'var(--surface-sunken)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: toggle,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      border: 'none',
      background: 'transparent',
      padding: 0,
      cursor: 'default',
      color: 'var(--text-body)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "sparkles",
    size: 13,
    color: "var(--brand)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      fontWeight: 'var(--weight-medium)'
    }
  }, title), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: open ? 'chevron.up' : 'chevron.down',
    size: 11,
    color: "var(--ink-2)"
  })), open ? error ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6,
      font: 'var(--type-callout)',
      color: 'var(--warn)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "exclamationmark.triangle",
    size: 12
  }), error) : loading && !text ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--ink-2)'
    }
  }, "\u6B63\u5728\u9605\u8BFB\u6539\u52A8\u2026") : /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--text-body)',
      textWrap: 'pretty'
    }
  }, text), !loading ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      font: 'var(--type-caption)',
      color: 'var(--ink-3)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "info.circle",
    size: 10
  }), "AI \u751F\u6210\u7684\u89E3\u91CA\u53EF\u80FD\u6709\u8BEF\uFF0C\u8BF7\u4EE5\u4EE3\u7801\u4E3A\u51C6") : null) : null);
}
Object.assign(__ds_scope, { ExplanationPanel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/ExplanationPanel.jsx", error: String((e && e.message) || e) }); }

// components/feedback/HazardDialog.jsx
try { (() => {
/**
 * 危险操作预警。一次答完三个问题：会发生什么、能不能撤销、怎么撤销。
 * 再附上等价的 git 命令（透明命令层）—— 这个 app 教你 Git，而不是把 Git 藏起来。
 */
function HazardDialog({
  title,
  whatHappens,
  undoable,
  howToUndo,
  command,
  confirmLabel,
  onConfirm,
  onCancel,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-section)',
      width: 460,
      padding: 'var(--space-major)',
      background: 'var(--surface-raised)',
      borderRadius: 'var(--radius-large)',
      boxShadow: 'var(--shadow-sheet)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "exclamationmark.triangle",
    size: 18,
    color: "var(--warn)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-title)',
      color: 'var(--text-body)'
    }
  }, title)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-loose)'
    }
  }, [['会发生什么', whatHappens], ['能不能撤销', undoable], ['怎么撤销', howToUndo]].map(([label, value]) => value ? /*#__PURE__*/React.createElement("div", {
    key: label,
    style: {
      display: 'flex',
      gap: 'var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      width: 72,
      textAlign: 'right',
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)',
      paddingTop: 1
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--text-body)',
      textWrap: 'pretty'
    }
  }, value)) : null)), command ? /*#__PURE__*/React.createElement("code", {
    style: {
      display: 'block',
      padding: 'var(--space-regular) var(--space-loose)',
      borderRadius: 'var(--radius-medium)',
      background: 'var(--surface-sunken)',
      font: 'var(--type-mono)',
      color: 'var(--ink-2)',
      overflowX: 'auto',
      whiteSpace: 'pre'
    }
  }, command) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'flex-end',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onCancel,
    style: {
      height: 24,
      padding: '0 12px',
      borderRadius: 'var(--radius-medium)',
      border: '1px solid var(--border-control)',
      background: 'var(--surface-app)',
      font: 'var(--type-body)',
      color: 'var(--text-body)',
      cursor: 'default'
    }
  }, "\u53D6\u6D88"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onConfirm,
    style: {
      height: 24,
      padding: '0 12px',
      borderRadius: 'var(--radius-medium)',
      border: 'none',
      background: 'var(--danger)',
      color: '#FFFFFF',
      font: 'var(--type-body)',
      fontWeight: 'var(--weight-medium)',
      cursor: 'default'
    }
  }, confirmLabel)));
}
Object.assign(__ds_scope, { HazardDialog });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/HazardDialog.jsx", error: String((e && e.message) || e) }); }

// components/feedback/TransferIndicator.jsx
try { (() => {
/** 工具栏上的传输进度。数字用等宽，避免每帧宽度跳动。 */
const SPIN_ID = 'yugit-spin-keyframes';
function TransferIndicator({
  label,
  style
}) {
  React.useEffect(() => {
    if (document.getElementById(SPIN_ID)) return;
    const tag = document.createElement('style');
    tag.id = SPIN_ID;
    tag.textContent = '@keyframes yugit-spin{to{transform:rotate(360deg)}}';
    document.head.appendChild(tag);
  }, []);
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 12,
      height: 12,
      borderRadius: '50%',
      border: '1.5px solid var(--hairline-strong)',
      borderTopColor: 'var(--ink-2)',
      animation: 'yugit-spin 0.7s linear infinite'
    }
  }), label ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, label) : null);
}
Object.assign(__ds_scope, { TransferIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/TransferIndicator.jsx", error: String((e && e.message) || e) }); }

// components/graph/LaneGraph.jsx
try { (() => {
/**
 * 一行的轨道与连线。整个客户端的门面就是它。
 *
 * 规则：
 * - 轨道间距对所有行必须一致，否则同一条轨道在相邻两行会错位、连不上。
 * - 轨道多到放不下时压缩间距（到 5 为止），而不是把图形区撑宽去挤标题。
 * - 选中行放弃区分轨道颜色，全部换成能压住强调色背景的前景色 ——
 *   丢掉的颜色只影响这一行，而这一行本来就靠背景高亮定位；
 *   「看不见」是更严重的问题。
 * - 节点靠形状区分：环 = 普通提交，实心点 = 合并，外圈细环 = HEAD。
 * - HEAD 外环用 --ink-1 深墨，不用品牌色：分支图是轨道色的地盘，品牌色进来只会
 *   多出一次「这是品牌还是某条分支」的判断。品牌色在侧栏、AI 入口、空状态出现。
 *
 * 几何量与 tokens/graph.css 一一对应（SVG 的 r/cx 属性吃不进 var()，
 * 所以这里是数字；线宽走 CSS 的 stroke-width，仍然读 token）。
 */
const GEOMETRY = {
  laneGap: 14,
  laneGapMin: 5,
  widthMin: 24,
  widthMax: 84,
  nodeR: 4.5,
  holeR: 2.6,
  mergeR: 3.2,
  headRingR: 6.5
};
const LANE_COUNT = 8;
const laneColor = index => 'var(--lane-' + (index % LANE_COUNT + 1) + ')';
function graphWidth(laneCount, laneGap) {
  const lanes = Math.max(laneCount || 1, 1);
  const gap = laneGap || GEOMETRY.laneGap;
  return Math.min(Math.max(GEOMETRY.widthMin, lanes * gap), GEOMETRY.widthMax);
}
function LaneGraph({
  row,
  laneCount = 1,
  laneGap = GEOMETRY.laneGap,
  height = 44,
  emphasized = false,
  rowBackground = 'var(--surface-app)',
  style
}) {
  const gap = Math.max(GEOMETRY.laneGapMin, Math.min(laneGap, GEOMETRY.widthMax / Math.max(laneCount, 1)));
  const width = graphWidth(laneCount, gap);
  const centerX = lane => lane * gap + gap / 2;
  const middle = height / 2;
  const color = index => emphasized ? 'var(--lane-on-emphasized)' : laneColor(index);
  return /*#__PURE__*/React.createElement("svg", {
    width: width,
    height: height,
    viewBox: '0 0 ' + width + ' ' + height,
    style: {
      flex: '0 0 auto',
      display: 'block',
      overflow: 'hidden',
      ...style
    }
  }, (row.links || []).map((link, i) => {
    const fromX = centerX(link.fromLane);
    const toX = centerX(link.toLane);
    const d = link.fromLane === link.toLane ? 'M ' + fromX + ' 0 L ' + fromX + ' ' + height : 'M ' + fromX + ' 0 C ' + fromX + ' ' + middle + ', ' + toX + ' ' + middle + ', ' + toX + ' ' + height;
    return /*#__PURE__*/React.createElement("path", {
      key: i,
      d: d,
      fill: "none",
      strokeLinecap: "round",
      stroke: color(link.colorIndex),
      style: {
        strokeWidth: link.isHead ? 'var(--graph-line-head)' : 'var(--graph-line)'
      }
    });
  }), row.isHead && !emphasized ? /*#__PURE__*/React.createElement("circle", {
    cx: centerX(row.nodeLane),
    cy: middle,
    r: GEOMETRY.headRingR,
    fill: "none",
    stroke: "var(--ink-1)",
    style: {
      strokeWidth: 'var(--graph-head-ring-w)'
    }
  }) : null, row.isMerge ? /*#__PURE__*/React.createElement("circle", {
    cx: centerX(row.nodeLane),
    cy: middle,
    r: GEOMETRY.mergeR,
    fill: color(row.colorIndex)
  }) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("circle", {
    cx: centerX(row.nodeLane),
    cy: middle,
    r: GEOMETRY.nodeR,
    fill: color(row.colorIndex)
  }), /*#__PURE__*/React.createElement("circle", {
    cx: centerX(row.nodeLane),
    cy: middle,
    r: GEOMETRY.holeR,
    fill: emphasized ? 'var(--selection-bg)' : rowBackground
  })));
}
Object.assign(__ds_scope, { GEOMETRY, LANE_COUNT, laneColor, graphWidth, LaneGraph });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/graph/LaneGraph.jsx", error: String((e && e.message) || e) }); }

// components/rows/BranchRow.jsx
try { (() => {
/**
 * 侧栏里的一行分支。
 * 当前分支：名字加粗 + 图标换品牌靛 + 左侧一根 2px 品牌色标记。
 * 「我现在在哪个分支上」是侧栏里最高频要确认的一件事，光靠加粗还不够快。
 * 名字从中间截断：origin/feature/... 两头都有信息。
 */
function BranchRow({
  name,
  isRemote = false,
  isCurrent = false,
  selected = false,
  ahead = 0,
  behind = 0,
  gone = false,
  title,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    title: title || name,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      height: 24,
      padding: '0 var(--space-regular)',
      borderRadius: 'var(--radius-medium)',
      background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
      color: selected ? 'var(--selection-fg)' : 'var(--text-body)',
      ...style
    }
  }, isCurrent && !selected ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 0,
      top: 5,
      bottom: 5,
      width: 2,
      borderRadius: 2,
      background: 'var(--brand)'
    }
  }) : null, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: isRemote ? 'cloud' : 'arrow.triangle.branch',
    size: 12,
    color: selected ? 'var(--selection-fg)' : isCurrent ? 'var(--brand)' : 'var(--ink-2)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: 'var(--type-body)',
      fontWeight: isCurrent ? 'var(--weight-semibold)' : 'var(--weight-regular)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl',
      textAlign: 'left'
    }
  }, name), /*#__PURE__*/React.createElement(__ds_scope.TrackingBadge, {
    ahead: ahead,
    behind: behind,
    gone: gone,
    emphasized: selected
  }));
}
Object.assign(__ds_scope, { BranchRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/BranchRow.jsx", error: String((e && e.message) || e) }); }

// components/rows/CommitRow.jsx
try { (() => {
/**
 * 历史列表里的一行：分支图 + 两行文字。行高 44。
 *
 * 元信息拆成三个独立文本而不是拼成一个字符串：拼字符串省事，但那样三样东西
 * 必然同字号同颜色 —— 想让 hash 更淡、时间右对齐都做不到，眼睛扫下来也分不出
 * 哪个重要。时间右对齐：不这么做，每行的视觉右边界随作者名长短参差不齐。
 */
function CommitRow({
  subject,
  hash,
  author,
  date,
  refs = [],
  isMerge = false,
  isHead = false,
  graphRow,
  laneCount = 1,
  selected = false,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  const background = selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'var(--surface-app)';
  const faded = selected ? 'color-mix(in srgb, var(--selection-fg) 72%, transparent)' : 'var(--ink-3)';
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'stretch',
      gap: 'var(--space-regular)',
      height: 44,
      paddingRight: 'var(--space-regular)',
      paddingLeft: 'var(--space-tight)',
      background,
      color: selected ? 'var(--selection-fg)' : 'var(--text-body)',
      ...style
    }
  }, graphRow ? /*#__PURE__*/React.createElement(__ds_scope.LaneGraph, {
    row: graphRow,
    laneCount: laneCount,
    height: 44,
    emphasized: selected,
    rowBackground: background
  }) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'center',
      gap: 2,
      minWidth: 0,
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      minWidth: 0
    }
  }, isMerge ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow.triangle.merge",
    size: 11,
    title: "\u5408\u5E76\u63D0\u4EA4",
    color: selected ? 'var(--selection-fg)' : 'var(--merge)'
  }) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, subject), refs.length ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4,
      flex: '0 0 auto'
    }
  }, refs.map((ref, i) => /*#__PURE__*/React.createElement(__ds_scope.RefBadge, {
    key: i,
    kind: ref.kind,
    emphasized: selected
  }, ref.name))) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--space-regular)',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-mono)',
      color: faded,
      flex: '0 0 auto'
    }
  }, hash), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: selected ? 'color-mix(in srgb, var(--selection-fg) 85%, transparent)' : 'var(--ink-2)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, author), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: faded,
      flex: '0 0 auto'
    }
  }, date))));
}
Object.assign(__ds_scope, { CommitRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/CommitRow.jsx", error: String((e && e.message) || e) }); }

// components/rows/DayGroupRow.jsx
try { (() => {
/**
 * 历史列表的日期分组行。
 *
 * 这是本版新加的东西，用来解决「提交列表每一行长得完全一样，眼睛没有落点」。
 * 24px 一条，粘在滚动顶部，只花一行高度换来整列的节奏，
 * 比给每一行加装饰便宜得多，也不动信息密度。
 */
function DayGroupRow({
  label,
  count,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-tight)',
      height: 24,
      padding: '0 var(--space-regular)',
      position: 'sticky',
      top: 0,
      zIndex: 1,
      background: 'var(--surface-sunken)',
      borderTop: '1px solid var(--hairline)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-secondary)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--ink-2)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", null, label), typeof count === 'number' ? /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--ink-4)',
      fontWeight: 'var(--weight-regular)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, count) : null);
}
Object.assign(__ds_scope, { DayGroupRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/DayGroupRow.jsx", error: String((e && e.message) || e) }); }

// components/rows/DirectoryRow.jsx
try { (() => {
/** 树形变更列表里的目录行。悬停才出现批量暂存按钮。 */
function DirectoryRow({
  name,
  count,
  collapsed = false,
  depth = 0,
  action,
  onToggle,
  title,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onToggle,
    title: title || name,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      height: 24,
      padding: '0 var(--space-regular)',
      paddingLeft: 'calc(var(--space-regular) + ' + depth * 12 + 'px)',
      background: hover ? 'var(--surface-hover)' : 'transparent',
      borderRadius: 'var(--radius-small)',
      color: 'var(--text-body)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron.right",
    size: 9,
    color: "var(--ink-2)",
    style: {
      transform: collapsed ? 'none' : 'rotate(90deg)',
      transition: 'transform var(--dur-fast) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "folder",
    size: 12,
    color: "var(--ink-2)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl',
      textAlign: 'left'
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-4)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, count), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      visibility: hover && action ? 'visible' : 'hidden'
    }
  }, action));
}
Object.assign(__ds_scope, { DirectoryRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/DirectoryRow.jsx", error: String((e && e.message) || e) }); }

// components/rows/FileRow.jsx
try { (() => {
/**
 * 变更列表里的一行文件。
 * 文件名从中间截断（两头都有信息：开头是模块，结尾是文件名）；
 * 目录副行从头部截断，最后一段离文件最近，也最能说明这是哪个目录。
 * 平铺模式才显示目录 —— 树里目录已经由缩进表达了，再显示一遍是噪音。
 */
function FileRow({
  status,
  name,
  directory,
  selected = false,
  depth = 0,
  onClick,
  title,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    title: title || name,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)',
      minHeight: directory ? 38 : 30,
      padding: '4px var(--space-regular)',
      paddingLeft: 'calc(var(--space-regular) + ' + depth * 12 + 'px)',
      borderRadius: 'var(--radius-small)',
      background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
      color: selected ? 'var(--selection-fg)' : 'var(--text-body)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.StatusLetter, {
    status: status,
    emphasized: selected
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 1,
      minWidth: 0,
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, name), directory ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: selected ? 'color-mix(in srgb, var(--selection-fg) 78%, transparent)' : 'var(--ink-2)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl',
      textAlign: 'left'
    }
  }, directory) : null));
}
Object.assign(__ds_scope, { FileRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/FileRow.jsx", error: String((e && e.message) || e) }); }

// components/rows/SectionHeader.jsx
try { (() => {
/**
 * 列表分组头：标题（带计数）+ 右侧动作。
 * 动作只在悬停时出现 —— 每个分组后面常挂一个按钮会很吵。
 * 文案照实说数量：筛选时是「暂存这 12 个」，不是「全部暂存」。
 */
function SectionHeader({
  title,
  count,
  tone = 'neutral',
  action,
  sticky = true,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-tight)',
      height: 22,
      padding: '0 var(--space-regular)',
      position: sticky ? 'sticky' : 'static',
      top: 0,
      zIndex: 1,
      background: 'var(--surface-sunken)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-secondary)',
      fontWeight: 'var(--weight-semibold)',
      color: tone === 'warn' ? 'var(--warn)' : 'var(--ink-2)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", null, title, typeof count === 'number' ? '（' + count + '）' : ''), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      visibility: hover && action ? 'visible' : 'hidden'
    }
  }, action));
}
Object.assign(__ds_scope, { SectionHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/SectionHeader.jsx", error: String((e && e.message) || e) }); }

// components/rows/TagRow.jsx
try { (() => {
/** 侧栏里的一行 tag。轻量 tag 标出来 —— 工程规范要求发布用附注 tag。 */
function TagRow({
  name,
  annotated = true,
  selected = false,
  title,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    title: title || name,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      height: 24,
      padding: '0 var(--space-regular)',
      borderRadius: 'var(--radius-medium)',
      background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
      color: selected ? 'var(--selection-fg)' : 'var(--text-body)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "tag",
    size: 12,
    color: selected ? 'var(--selection-fg)' : 'var(--ink-2)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      font: 'var(--type-body)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, name), !annotated ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: selected ? 'var(--selection-fg)' : 'var(--ink-4)'
    }
  }, "\u8F7B\u91CF") : null);
}
Object.assign(__ds_scope, { TagRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rows/TagRow.jsx", error: String((e && e.message) || e) }); }

// ui_kits/first-run/Tour.jsx
try { (() => {
/* 新手引导 sheet，520×380。对应 Teaching/OnboardingView.swift，
   文案取自 GitKit 的 OnboardingStep.repositoryTour，一字未改。
   目标不是教会 Git 的全部概念，而是让第一次用的人知道这个界面上哪里能做什么。 */
const {
  Button,
  Icon
} = window.Git_c7d67c;
const STEPS = [{
  id: 'changes',
  title: '中间一栏是你改了什么',
  detail: '所有还没提交的改动都在这里。点一个文件，右边会显示具体改了哪几行。',
  concept: '「工作区」就是你正在编辑的这些文件本身。'
}, {
  id: 'stage',
  title: '挑出这次要提交的部分',
  detail: '整个文件可以一键暂存；也可以在右边的 diff 上只暂存某一块、甚至某几行。',
  concept: '「暂存区」是一个中转站：先把想一起提交的改动放进去，再一次提交。这让你可以把一次编辑拆成几个独立的提交。'
}, {
  id: 'commit',
  title: '写一句话说清这次改了什么',
  detail: '在下面的框里写提交信息。配了 AI 的话可以让它先起个草稿，再自己改。',
  concept: '「提交」是一个存档点。存下之后随时能回到这一刻。'
}, {
  id: 'history',
  title: '切到「历史」看走过的路',
  detail: '每一条都是一个存档点。右键某条提交可以直接合并、改写信息或丢弃它。',
  concept: '「分支」是同一份历史上的不同岔路，切换分支就是切换到另一条路上。'
}, {
  id: 'timeline',
  title: '做错了从时间线退回来',
  detail: '危险操作执行前会自动留一个可恢复的时间点，⌘Z 能退回上一步之前。',
  concept: '这是驭Git 额外做的事：连「还没提交的改动被覆盖」也能找回来，而这在 git 自己那里是做不到的。'
}, {
  id: 'palette',
  title: '记不住在哪就按 ⌘K',
  detail: '命令面板列出当前能做的所有操作，每条旁边写着等价的 git 命令。',
  concept: '看多了那些命令，你就顺带把 Git 学会了。'
}];
function Tour({
  onFinish
}) {
  const [index, setIndex] = React.useState(0);
  const step = STEPS[index];
  const last = index === STEPS.length - 1;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 520,
      height: 380,
      display: 'flex',
      flexDirection: 'column',
      background: 'var(--surface-raised)',
      borderRadius: 'var(--radius-large)',
      border: '1px solid var(--hairline)',
      boxShadow: 'var(--shadow-sheet)',
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 14,
      padding: 20,
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, "\u7B2C ", index + 1, " / ", STEPS.length, " \u6B65"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small",
    onClick: onFinish
  }, "\u8DF3\u8FC7")), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--text-size-sheet-title)',
      fontWeight: 'var(--weight-semibold)'
    }
  }, step.title), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--text-body)',
      textWrap: 'pretty'
    }
  }, step.detail), step.concept ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-tight)',
      padding: 10,
      background: 'var(--surface-sunken)',
      borderRadius: 'var(--radius-medium)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      font: 'var(--type-caption)',
      fontWeight: 'var(--weight-medium)',
      color: 'var(--ink-2)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lightbulb",
    size: 11
  }), "\u987A\u5E26\u4E00\u63D0"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--ink-2)',
      textWrap: 'pretty'
    }
  }, step.concept)) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)',
      padding: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 5
    }
  }, STEPS.map((s, i) => /*#__PURE__*/React.createElement("span", {
    key: s.id,
    style: {
      width: 6,
      height: 6,
      borderRadius: '50%',
      background: i === index ? 'var(--brand)' : 'color-mix(in srgb, var(--ink-2) 30%, transparent)'
    }
  }))), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    disabled: index === 0,
    onClick: () => setIndex(index - 1)
  }, "\u4E0A\u4E00\u6B65"), last ? /*#__PURE__*/React.createElement(Button, {
    variant: "default",
    onClick: onFinish
  }, "\u5F00\u59CB\u4F7F\u7528") : /*#__PURE__*/React.createElement(Button, {
    variant: "default",
    onClick: () => setIndex(index + 1)
  }, "\u4E0B\u4E00\u6B65")));
}
Object.assign(window, {
  Tour,
  STEPS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/first-run/Tour.jsx", error: String((e && e.message) || e) }); }

// ui_kits/first-run/Welcome.jsx
try { (() => {
/* 欢迎页：没打开仓库时的入口。
   对应 Repository/RootView.swift 的 WelcomeView —— 品牌标志换成靛底白「驭」的字组，
   这是整个应用里唯一一处可以放品牌的地方（仓库里没有图形 logo）。 */
const {
  Button,
  Icon
} = window.Git_c7d67c;
const RECENTS = [{
  name: 'ai-cloud',
  path: '~/Developer/tvjoy'
}, {
  name: 'Yu-Git',
  path: '~/Developer/oss'
}, {
  name: 'kino-web',
  path: '~/Developer/tvjoy/frontend'
}];
function Welcome({
  onOpen
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 'var(--space-major)',
      height: '100%',
      padding: 40,
      background: 'var(--surface-app)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 96,
      height: 96,
      borderRadius: 22,
      background: 'var(--brand)',
      color: 'var(--brand-on)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--text-size-mark)',
      fontWeight: 'var(--weight-semibold)'
    }
  }, "\u9A6D"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--text-size-display)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: 'var(--tracking-display)'
    }
  }, "\u9A6DGit"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-callout)',
      color: 'var(--ink-2)'
    }
  }, "AI \u5E2E\u4F60\u5199\u4EE3\u7801\uFF0C\u9A6DGit \u5E2E\u4F60\u9A7E\u9A6D\u5B83")), /*#__PURE__*/React.createElement(Button, {
    variant: "default",
    size: "large",
    icon: "folder",
    onClick: onOpen,
    title: "\u2318O",
    style: {
      minWidth: 140
    }
  }, "\u6253\u5F00\u4ED3\u5E93\u2026"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      width: 360
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, "\u6700\u8FD1\u6253\u5F00"), RECENTS.map(r => /*#__PURE__*/React.createElement("div", {
    key: r.name,
    onClick: onOpen,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)',
      padding: '4px 6px',
      borderRadius: 'var(--radius-small)'
    },
    onMouseEnter: e => {
      e.currentTarget.style.background = 'var(--surface-hover)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.background = 'transparent';
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "folder",
    size: 14,
    color: "var(--ink-2)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)'
    }
  }, r.name), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, r.path))))));
}
Object.assign(window, {
  Welcome
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/first-run/Welcome.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/ChangesPane.jsx
try { (() => {
/* 中栏 · 变更：过滤 + 冲突/已暂存/未暂存三段 + 底部提交面板。 */
const {
  FilterField,
  SectionHeader,
  FileRow,
  DirectoryRow,
  Button,
  Checkbox,
  EmptyState,
  Icon,
  ToolbarButton
} = window.Git_c7d67c;
const fileName = path => path.split('/').pop();
const dirName = path => path.split('/').slice(0, -1).join('/');
function ContextMenu({
  x,
  y,
  items,
  onClose
}) {
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: 'fixed',
      inset: 0,
      zIndex: 40
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      left: x,
      top: y,
      minWidth: 160,
      padding: 4,
      background: 'var(--surface-raised)',
      border: '1px solid var(--hairline)',
      borderRadius: 'var(--radius-medium)',
      boxShadow: 'var(--shadow-popover)'
    }
  }, items.map(item => /*#__PURE__*/React.createElement("div", {
    key: item.label,
    onClick: item.onClick,
    style: {
      display: 'flex',
      alignItems: 'center',
      height: 22,
      padding: '0 8px',
      borderRadius: 'var(--radius-small)',
      font: 'var(--type-body)',
      color: item.destructive ? 'var(--danger)' : 'var(--text-body)'
    },
    onMouseEnter: e => {
      e.currentTarget.style.background = 'var(--surface-hover)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.background = 'transparent';
    }
  }, item.label))));
}
function CommitPanel({
  message,
  onMessage,
  amend,
  onAmend,
  staged,
  onCommit,
  onDraft,
  drafting
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      padding: 10,
      borderTop: '1px solid var(--hairline)',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("textarea", {
    value: message,
    onChange: e => onMessage(e.target.value),
    placeholder: "\u63D0\u4EA4\u8BF4\u660E",
    style: {
      width: '100%',
      height: 72,
      resize: 'none',
      boxSizing: 'border-box',
      padding: '6px 8px',
      borderRadius: 'var(--radius-medium)',
      border: '1px solid var(--hairline-strong)',
      background: 'var(--surface-app)',
      font: 'var(--type-body)',
      color: 'var(--text-body)',
      outline: 'none'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement(Checkbox, {
    checked: amend,
    onChange: onAmend,
    label: "\u4FEE\u6539\u4E0A\u4E00\u6761\u63D0\u4EA4"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "checkmark.shield",
    disabled: !staged,
    title: staged ? '提交前让 AI 通读暂存的改动，按风险分级列出值得确认的地方' : '先暂存一些改动'
  }, "\u81EA\u67E5"), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "sparkles",
    onClick: onDraft,
    disabled: !staged || drafting,
    title: "\u6839\u636E\u6682\u5B58\u7684\u6539\u52A8\u8D77\u8349\u63D0\u4EA4\u4FE1\u606F\uFF0C\u751F\u6210\u540E\u53EF\u76F4\u63A5\u7F16\u8F91"
  }, drafting ? '起草中…' : 'AI 起草'), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    variant: "default",
    onClick: onCommit,
    disabled: !staged || !message.trim()
  }, "\u63D0\u4EA4")), amend ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      font: 'var(--type-caption)',
      color: 'var(--warn)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "exclamationmark.triangle",
    size: 10
  }), "\u4FEE\u6539\u540E commit hash \u4F1A\u53D8\uFF0C\u82E5\u5DF2\u63A8\u9001\u5219\u9700\u8981 force push") : null);
}
function ChangesPane({
  fixtures,
  selected,
  onSelect,
  onDiscard,
  onResolve
}) {
  const [filter, setFilter] = React.useState('');
  const [tree, setTree] = React.useState(true);
  const [collapsed, setCollapsed] = React.useState([]);
  const [message, setMessage] = React.useState('');
  const [amend, setAmend] = React.useState(false);
  const [drafting, setDrafting] = React.useState(false);
  const [menu, setMenu] = React.useState(null);
  const {
    changes
  } = fixtures;
  const match = e => !filter.trim() || e.path.toLowerCase().includes(filter.trim().toLowerCase());
  const staged = changes.staged.filter(match);
  const unstaged = changes.unstaged.filter(match);
  const conflicted = changes.conflicted.filter(match);
  const total = changes.staged.length + changes.unstaged.length;
  const draft = () => {
    setDrafting(true);
    window.setTimeout(() => {
      setMessage('fix(导航): 弹窗下边距收到 0.5rem，并补齐三处语言包文案');
      setDrafting(false);
    }, 900);
  };
  const rowsFor = (entries, isStaged) => {
    if (!tree) {
      return entries.map(e => /*#__PURE__*/React.createElement(FileRow, {
        key: e.path,
        status: e.status,
        name: e.path,
        selected: selected === e.path,
        onClick: () => onSelect(e.path, isStaged),
        style: {
          marginBottom: 1
        }
      }));
    }
    // 单子目录链合并成一行：上百个文件的变更列表靠它才读得下来
    const groups = {};
    entries.forEach(e => {
      (groups[dirName(e.path)] = groups[dirName(e.path)] || []).push(e);
    });
    return Object.entries(groups).map(([dir, items]) => /*#__PURE__*/React.createElement(React.Fragment, {
      key: dir
    }, /*#__PURE__*/React.createElement(DirectoryRow, {
      name: dir,
      count: items.length,
      collapsed: collapsed.includes(dir),
      onToggle: () => setCollapsed(collapsed.includes(dir) ? collapsed.filter(d => d !== dir) : [...collapsed, dir]),
      action: /*#__PURE__*/React.createElement(Button, {
        variant: "borderless",
        size: "small"
      }, isStaged ? '取消' : '暂存')
    }), collapsed.includes(dir) ? null : items.map(e => /*#__PURE__*/React.createElement(FileRow, {
      key: e.path,
      depth: 1,
      status: e.status,
      name: fileName(e.path),
      selected: selected === e.path,
      onClick: () => onSelect(e.path, isStaged),
      onContextMenu: undefined,
      style: {
        marginBottom: 1
      }
    }))));
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, total > 8 || filter ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      padding: '0 var(--space-regular) 6px'
    }
  }, /*#__PURE__*/React.createElement(FilterField, {
    value: filter,
    onChange: setFilter,
    placeholder: "\u8FC7\u6EE4\u6587\u4EF6\u8DEF\u5F84"
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: tree ? 'square.stack.3d.up' : 'text.alignleft',
    title: tree ? '改为平铺显示完整路径' : '改为按目录分组',
    onClick: () => setTree(!tree)
  })) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      minHeight: 0
    },
    onContextMenu: e => {
      e.preventDefault();
      setMenu({
        x: e.clientX,
        y: e.clientY
      });
    }
  }, !staged.length && !unstaged.length && !conflicted.length ? filter ? /*#__PURE__*/React.createElement(EmptyState, {
    icon: "magnifyingglass",
    title: "\u6CA1\u6709\u5339\u914D\u7684\u6587\u4EF6",
    description: "\u8BD5\u8BD5\u522B\u7684\u5173\u952E\u8BCD",
    compact: true
  }) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "checkmark.circle",
    title: "\u5DE5\u4F5C\u533A\u5E72\u51C0",
    description: "\u6CA1\u6709\u5F85\u5904\u7406\u7684\u6539\u52A8",
    compact: true
  }) : null, conflicted.length ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "\u51B2\u7A81",
    count: conflicted.length,
    tone: "warn",
    action: /*#__PURE__*/React.createElement(Button, {
      variant: "borderless",
      size: "small",
      onClick: onResolve
    }, "\u89E3\u51B3\u2026")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, rowsFor(conflicted, false))) : null, staged.length ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "\u5DF2\u6682\u5B58",
    count: staged.length,
    action: /*#__PURE__*/React.createElement(Button, {
      variant: "borderless",
      size: "small"
    }, filter ? '取消这 ' + staged.length + ' 个' : '全部取消')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, rowsFor(staged, true))) : null, unstaged.length ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "\u672A\u6682\u5B58",
    count: unstaged.length,
    action: /*#__PURE__*/React.createElement(Button, {
      variant: "borderless",
      size: "small"
    }, filter ? '暂存这 ' + unstaged.length + ' 个' : '全部暂存')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, rowsFor(unstaged, false))) : null), /*#__PURE__*/React.createElement(CommitPanel, {
    message: message,
    onMessage: setMessage,
    amend: amend,
    onAmend: setAmend,
    staged: staged.length > 0,
    drafting: drafting,
    onDraft: draft,
    onCommit: () => setMessage('')
  }), menu ? /*#__PURE__*/React.createElement(ContextMenu, {
    x: menu.x,
    y: menu.y,
    onClose: () => setMenu(null),
    items: [{
      label: '暂存',
      onClick: () => setMenu(null)
    }, {
      label: '在 Finder 中显示',
      onClick: () => setMenu(null)
    }, {
      label: '丢弃改动…',
      destructive: true,
      onClick: () => {
        setMenu(null);
        onDiscard();
      }
    }]
  }) : null);
}
Object.assign(window, {
  ChangesPane,
  CommitPanel,
  ContextMenu
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/ChangesPane.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/CommandPalette.jsx
try { (() => {
/* 命令面板。⌘K 唤起，输入即筛选（子序列匹配），右侧显示等价 git 命令。
   560×380，输入框 20pt —— 和应用里一致。 */
const {
  Icon,
  EmptyState
} = window.Git_c7d67c;
function subsequence(query, text) {
  const haystack = text.toLowerCase();
  let index = 0;
  for (const ch of query.toLowerCase()) {
    const found = haystack.indexOf(ch, index);
    if (found < 0) return false;
    index = found + 1;
  }
  return true;
}
function CommandPalette({
  commands,
  onClose
}) {
  const [query, setQuery] = React.useState('');
  const [active, setActive] = React.useState(0);
  const list = commands.filter(c => !query.trim() || subsequence(query.trim(), c.title) || subsequence(query.trim(), c.hint || '') || subsequence(query.trim(), c.cmd || ''));
  React.useEffect(() => {
    const onKey = e => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setActive(a => Math.min(a + 1, list.length - 1));
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setActive(a => Math.max(a - 1, 0));
      }
      if (e.key === 'Enter') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [list.length, onClose]);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: 'absolute',
      inset: 0,
      zIndex: 30,
      display: 'flex',
      justifyContent: 'center',
      paddingTop: 80,
      background: 'rgba(0,0,0,0.10)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      width: 560,
      height: 380,
      display: 'flex',
      flexDirection: 'column',
      background: 'var(--surface-raised)',
      borderRadius: 'var(--radius-large)',
      border: '1px solid var(--hairline)',
      boxShadow: 'var(--shadow-sheet)',
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: 12
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "command",
    size: 16,
    color: "var(--ink-2)"
  }), /*#__PURE__*/React.createElement("input", {
    autoFocus: true,
    value: query,
    placeholder: "\u8F93\u5165\u547D\u4EE4",
    onChange: e => {
      setQuery(e.target.value);
      setActive(0);
    },
    style: {
      flex: 1,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--text-size-sheet-title)',
      color: 'var(--text-body)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)',
      overflowY: 'auto',
      flex: 1,
      minHeight: 0
    }
  }, list.length ? list.map((c, i) => /*#__PURE__*/React.createElement("div", {
    key: c.title,
    onMouseEnter: () => setActive(i),
    onClick: onClose,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      minHeight: 38,
      padding: '3px var(--space-loose)',
      background: i === active ? 'color-mix(in srgb, var(--accent) 15%, transparent)' : 'transparent'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: c.icon,
    size: 16,
    color: "var(--accent)",
    style: {
      width: 18
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)'
    }
  }, c.title), c.hint ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, c.hint) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), c.cmd ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-mono)',
      color: 'var(--ink-3)',
      maxWidth: 200,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl'
    }
  }, c.cmd) : null)) : /*#__PURE__*/React.createElement("div", {
    style: {
      height: 240
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    icon: "magnifyingglass",
    title: '没有匹配「' + query + '」的命令',
    description: "\u8BD5\u8BD5\u300C\u6574\u7406\u300D\u300C\u6682\u5B58\u300D\u300C\u65F6\u95F4\u7EBF\u300D",
    compact: true
  })))));
}
Object.assign(window, {
  CommandPalette
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/CommandPalette.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/DetailPane.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* 右栏：选中文件时显示 diff，选中提交时显示提交信息 + 改动的文件（下半部分是该文件的 diff）。 */
const {
  Icon,
  Button,
  CopyButton,
  CountPill,
  RefBadge,
  StatusLetter,
  EmptyState,
  ExplanationPanel,
  DiffLine,
  HunkHeader,
  SelectionBar,
  ToolbarButton
} = window.Git_c7d67c;
function DiffBody({
  diff,
  selection,
  onToggleLine,
  wrap
}) {
  const widest = diff.hunks.flatMap(h => h.lines).reduce((m, l) => Math.max(m, l.oldNumber || 0, l.newNumber || 0), 0);
  const gutter = Math.max(String(widest).length, 2) * 7 + 10;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: 'auto',
      minHeight: 0,
      background: 'var(--surface-app)'
    }
  }, diff.hunks.map((hunk, hi) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: hunk.header
  }, /*#__PURE__*/React.createElement(HunkHeader, {
    header: hunk.header,
    action: /*#__PURE__*/React.createElement(Button, {
      variant: "borderless",
      size: "small"
    }, "\u6682\u5B58\u6B64\u5757")
  }), hunk.lines.map((line, li) => /*#__PURE__*/React.createElement(DiffLine, _extends({
    key: hi + '-' + li
  }, line, {
    gutterWidth: gutter,
    wrap: wrap,
    selected: (selection[hi] || []).includes(li),
    onClick: () => onToggleLine(hi, li)
  }))))));
}
function FileDetail({
  diff,
  isStaged,
  onBlame
}) {
  const [selection, setSelection] = React.useState({});
  const [wrap, setWrap] = React.useState(false);
  const count = Object.values(selection).reduce((n, lines) => n + lines.length, 0);
  const toggleLine = (hi, li) => {
    const lines = selection[hi] || [];
    const next = lines.includes(li) ? lines.filter(l => l !== li) : [...lines, li];
    setSelection({
      ...selection,
      [hi]: next
    });
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '8px var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "doc.text",
    size: 13,
    color: "var(--ink-2)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl',
      textAlign: 'left'
    }
  }, diff.path), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4,
      font: 'var(--type-mono)',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--diff-add-fg)'
    }
  }, "+", diff.added), /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--diff-del-fg)'
    }
  }, "\u2212", diff.deleted)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small",
    onClick: onBlame,
    title: "\u9010\u884C\u770B\u8FD9\u6BB5\u4EE3\u7801\u662F\u8C01\u5199\u7684\uFF1A\u4EBA\uFF0C\u8FD8\u662F\u54EA\u4E2A AI \u5DE5\u5177"
  }, "\u67E5\u770B\u5F52\u56E0"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small"
  }, isStaged ? '取消暂存整个文件' : '暂存整个文件'), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: wrap ? 'text.alignleft' : 'arrow.left.and.right',
    title: wrap ? '改为不折行（长行横向滚动）' : '折行显示长行',
    onClick: () => setWrap(!wrap)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px var(--space-loose) 0'
    }
  }, /*#__PURE__*/React.createElement(ExplanationPanel, {
    title: "\u7528\u4E2D\u6587\u8BB2\u8BB2\u8FD9\u4EFD\u6539\u52A8",
    text: "\u8FD9\u4EFD\u6539\u52A8\u628A\u5BFC\u822A\u680F\u5F39\u7A97\u7684\u4E0B\u8FB9\u8DDD\u4ECE 1rem \u6536\u5230 0.5rem\uFF0C\u5E76\u65B0\u589E\u4E86\u4E00\u6BB5\u5E38\u9A7B\u7684\u8FC1\u79FB\u5165\u53E3\u5BB9\u5668\uFF1B\u5220\u6389\u7684 legacy \u5F00\u5173\u8BF4\u660E\u65E7\u5165\u53E3\u5DF2\u7ECF\u4E0D\u518D\u9700\u8981\u3002\u90FD\u662F\u5C55\u793A\u5C42\u6539\u52A8\uFF0C\u6CA1\u6709\u89E6\u78B0\u63A5\u53E3\u3002"
  })), count > 0 ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 8
    }
  }, /*#__PURE__*/React.createElement(SelectionBar, {
    count: count,
    primaryLabel: isStaged ? '取消暂存选中的行' : '暂存选中的行',
    onClear: () => setSelection({}),
    onApply: () => setSelection({})
  })) : /*#__PURE__*/React.createElement("div", {
    style: {
      height: 8
    }
  }), /*#__PURE__*/React.createElement(DiffBody, {
    diff: diff,
    selection: selection,
    onToggleLine: toggleLine,
    wrap: wrap
  }));
}
function MetaRow({
  label,
  value,
  secondary,
  mono,
  trailing
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      width: 52,
      textAlign: 'right',
      paddingTop: 1,
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)'
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-tight)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: mono ? 'var(--type-mono)' : 'var(--type-body)'
    }
  }, value), trailing), secondary ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-3)'
    }
  }, secondary) : null));
}
function CommitDetail({
  commit,
  files,
  diff,
  selectedFile,
  onSelectFile
}) {
  const [split, setSplit] = React.useState(0.48);
  const dragging = React.useRef(false);
  const wrapRef = React.useRef(null);
  React.useEffect(() => {
    const move = e => {
      if (!dragging.current || !wrapRef.current) return;
      const box = wrapRef.current.getBoundingClientRect();
      setSplit(Math.min(0.78, Math.max(0.22, (e.clientY - box.top) / box.height)));
    };
    const up = () => {
      dragging.current = false;
    };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    return () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
    };
  }, []);
  const summary = /*#__PURE__*/React.createElement("div", {
    style: {
      overflowY: 'auto',
      minHeight: 0,
      flex: selectedFile ? 'none' : 1,
      height: selectedFile ? split * 100 + '%' : 'auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-section)',
      padding: 'var(--space-section)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-title)',
      textWrap: 'pretty'
    }
  }, commit.subject), commit.refs && commit.refs.length ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4
    }
  }, commit.refs.map(r => /*#__PURE__*/React.createElement(RefBadge, {
    key: r.name,
    kind: r.kind
  }, r.name))) : null), /*#__PURE__*/React.createElement(ExplanationPanel, {
    title: "\u7528\u4E2D\u6587\u8BB2\u8BB2\u8FD9\u6B21 commit",
    text: "\u8FD9\u6B21\u63D0\u4EA4\u53EA\u6539\u4E86\u5BFC\u822A\u680F\u7684\u5F39\u7A97\u6837\u5F0F\uFF1A\u4E0B\u8FB9\u8DDD\u6536\u7A84\u4E00\u6863\uFF0C\u5E76\u8865\u9F50\u4E86\u4E09\u5904\u8BED\u8A00\u5305\u6587\u6848\u3002\u5C5E\u4E8E\u7EAF\u5C55\u793A\u5C42\u8C03\u6574\uFF0C\u4E0D\u5F71\u54CD\u63A5\u53E3\u4E0E\u6570\u636E\u3002"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement(MetaRow, {
    label: "\u63D0\u4EA4",
    value: commit.hash,
    mono: true,
    trailing: /*#__PURE__*/React.createElement(CopyButton, {
      text: commit.hash + '9d0e4a1b',
      title: "\u590D\u5236\u5B8C\u6574 commit hash"
    })
  }), /*#__PURE__*/React.createElement(MetaRow, {
    label: "\u4F5C\u8005",
    value: commit.author,
    secondary: '15304991+li-zlincold@user.noreply.gitee.com · 2026年3月31日 1:29'
  }), /*#__PURE__*/React.createElement(MetaRow, {
    label: commit.isMerge ? '父提交（合并）' : '父提交',
    value: commit.isMerge ? '7dd04b9dd  ebdeefc6d' : '7dd04b9dd',
    mono: true
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-tight)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-title)'
    }
  }, "\u6539\u52A8\u7684\u6587\u4EF6"), /*#__PURE__*/React.createElement(CountPill, null, files.length)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column'
    }
  }, files.map(f => {
    const selected = selectedFile === f.path;
    return /*#__PURE__*/React.createElement("div", {
      key: f.path,
      onClick: () => onSelectFile(selected ? null : f.path),
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-regular)',
        padding: '5px var(--space-regular)',
        borderRadius: 'var(--radius-small)',
        background: selected ? 'var(--selection-bg)' : 'transparent',
        color: selected ? 'var(--selection-fg)' : 'var(--text-body)'
      }
    }, /*#__PURE__*/React.createElement(StatusLetter, {
      status: f.status,
      emphasized: selected
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        font: 'var(--type-body)',
        minWidth: 0,
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
        direction: 'rtl',
        textAlign: 'left'
      }
    }, f.path));
  })))));
  if (!selectedFile) return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, summary);
  return /*#__PURE__*/React.createElement("div", {
    ref: wrapRef,
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, summary, /*#__PURE__*/React.createElement("div", {
    onMouseDown: () => {
      dragging.current = true;
    },
    style: {
      height: 5,
      cursor: 'row-resize',
      background: 'var(--hairline)',
      flex: '0 0 auto'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-regular)',
      padding: '8px var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap',
      direction: 'rtl',
      textAlign: 'left'
    }
  }, selectedFile), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4,
      font: 'var(--type-mono)',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--diff-add-fg)'
    }
  }, "+", diff.added), /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--diff-del-fg)'
    }
  }, "\u2212", diff.deleted)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small",
    onClick: () => onSelectFile(null)
  }, "\u6536\u8D77")), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)'
    }
  }), /*#__PURE__*/React.createElement(DiffBody, {
    diff: diff,
    selection: {},
    onToggleLine: () => {},
    wrap: false
  })));
}
function DetailPane({
  fixtures,
  selectedFile,
  isStaged,
  selectedCommit,
  onBlame
}) {
  const [commitFile, setCommitFile] = React.useState(fixtures.commitFiles[0].path);
  const commit = fixtures.commits.find(c => c.hash === selectedCommit);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minWidth: 0,
      background: 'var(--surface-app)'
    }
  }, selectedFile ? /*#__PURE__*/React.createElement(FileDetail, {
    diff: {
      ...fixtures.diff,
      path: selectedFile
    },
    isStaged: isStaged,
    onBlame: onBlame
  }) : commit ? /*#__PURE__*/React.createElement(CommitDetail, {
    commit: commit,
    files: fixtures.commitFiles,
    diff: fixtures.diff,
    selectedFile: commitFile,
    onSelectFile: setCommitFile
  }) : /*#__PURE__*/React.createElement(EmptyState, {
    icon: "sidebar.right",
    title: "\u672A\u9009\u62E9\u5185\u5BB9",
    description: "\u5728\u5DE6\u4FA7\u9009\u62E9\u4E00\u4E2A\u6587\u4EF6\u6216\u63D0\u4EA4"
  }));
}
Object.assign(window, {
  DetailPane,
  CommitDetail,
  FileDetail,
  DiffBody,
  MetaRow
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/DetailPane.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/HistoryPane.jsx
try { (() => {
/* 中栏 · 历史：搜提交信息 + 作者/时间筛选 + 日期分组的提交列表。 */
const {
  FilterField,
  CommitRow,
  DayGroupRow,
  ToolbarButton,
  EmptyState,
  Button,
  Icon
} = window.Git_c7d67c;
function HistoryPane({
  fixtures,
  selected,
  onSelect
}) {
  const [filter, setFilter] = React.useState('');
  const [author, setAuthor] = React.useState(null);
  const commits = fixtures.commits.filter(c => {
    const q = filter.trim().toLowerCase();
    const okText = !q || c.subject.toLowerCase().includes(q) || c.hash.includes(q);
    return okText && (!author || c.author === author);
  });

  // 日期变了就插一条分组行 —— 几百条等高的提交里，这是眼睛唯一的落点
  const blocks = [];
  commits.forEach(c => {
    const last = blocks[blocks.length - 1];
    if (!last || last.day !== c.day) blocks.push({
      day: c.day,
      items: [c]
    });else last.items.push(c);
  });
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      padding: '0 var(--space-regular) 6px'
    }
  }, /*#__PURE__*/React.createElement(FilterField, {
    value: filter,
    onChange: setFilter,
    placeholder: "\u641C\u63D0\u4EA4\u4FE1\u606F"
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: author ? 'person.circle' : 'person',
    title: "\u6309\u4F5C\u8005\u6216\u65F6\u95F4\u7B5B\u9009",
    active: !!author,
    onClick: () => setAuthor(author ? null : 'wangjun')
  })), filter || author ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      padding: '0 var(--space-regular) 6px'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "line.3.horizontal.decrease",
    size: 10,
    color: "var(--brand)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)'
    }
  }, "\u5728\u6574\u4E2A\u5386\u53F2\u4E2D\u627E\u5230 ", commits.length, " \u6761", author ? ' · 作者 ' + author : ''), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small",
    onClick: () => {
      setFilter('');
      setAuthor(null);
    }
  }, "\u6E05\u9664")) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      minHeight: 0,
      borderTop: '1px solid var(--hairline)'
    }
  }, commits.length === 0 ? /*#__PURE__*/React.createElement(EmptyState, {
    icon: "magnifyingglass",
    title: "\u6CA1\u6709\u5339\u914D\u7684\u63D0\u4EA4",
    description: "\u6574\u4E2A\u5386\u53F2\u91CC\u90FD\u6CA1\u6709\u7B26\u5408\u8FD9\u4E9B\u6761\u4EF6\u7684\u63D0\u4EA4",
    compact: true
  }) : blocks.map(block => /*#__PURE__*/React.createElement(React.Fragment, {
    key: block.day
  }, /*#__PURE__*/React.createElement(DayGroupRow, {
    label: block.day,
    count: block.items.length
  }), block.items.map(c => /*#__PURE__*/React.createElement(CommitRow, {
    key: c.hash,
    subject: c.subject,
    hash: c.hash,
    author: c.author,
    date: c.date,
    isMerge: c.isMerge,
    refs: c.refs,
    laneCount: fixtures.LANES,
    graphRow: {
      nodeLane: c.lane,
      colorIndex: c.lane,
      isMerge: c.isMerge,
      isHead: c.isHead,
      links: c.links
    },
    selected: selected === c.hash,
    onClick: () => onSelect(c.hash)
  })))), commits.length ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'center',
      padding: 'var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-secondary)',
      color: 'var(--ink-4)'
    }
  }, "\u6EDA\u52A8\u5230\u5E95\u90E8\u4F1A\u81EA\u52A8\u52A0\u8F7D\u66F4\u591A")) : null));
}
Object.assign(window, {
  HistoryPane
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/HistoryPane.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/Sidebar.jsx
try { (() => {
/* 左栏：过滤框 + 本地分支 / 远程分支（可折叠带计数）/ 标签。 */
const {
  FilterField,
  SectionHeader,
  BranchRow,
  TagRow,
  Button,
  Icon,
  EmptyState
} = window.Git_c7d67c;
function Disclosure({
  title,
  count,
  expanded,
  onToggle
}) {
  return /*#__PURE__*/React.createElement("div", {
    onClick: onToggle,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      height: 22,
      padding: '0 var(--space-regular)',
      position: 'sticky',
      top: 0,
      zIndex: 1,
      background: 'var(--surface-sunken)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-secondary)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--ink-2)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 9,
    style: {
      transform: expanded ? 'rotate(90deg)' : 'none',
      transition: 'transform var(--dur-fast) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement("span", null, title), /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--ink-4)',
      fontWeight: 'var(--weight-regular)'
    }
  }, count));
}
function Sidebar({
  fixtures,
  selected,
  onSelect
}) {
  const [filter, setFilter] = React.useState('');
  const [remoteOpen, setRemoteOpen] = React.useState(false);
  const [tagsOpen, setTagsOpen] = React.useState(false);
  const match = name => !filter.trim() || name.toLowerCase().includes(filter.trim().toLowerCase());

  // 当前分支永远置顶：光按最后提交时间排，切到很久没动的分支后它会沉到末尾，
  // 而那恰恰是你此刻站着的地方。
  const locals = fixtures.localBranches.filter(b => match(b.name));
  const ordered = [...locals.filter(b => b.isCurrent), ...locals.filter(b => !b.isCurrent)];
  const remotes = fixtures.remoteBranches.filter(b => match(b.name));
  const tags = fixtures.tags.filter(t => match(t.name));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 'var(--col-sidebar)',
      flex: '0 0 auto',
      display: 'flex',
      flexDirection: 'column',
      background: 'var(--surface-sidebar)',
      backdropFilter: 'var(--blur-sidebar)',
      WebkitBackdropFilter: 'var(--blur-sidebar)',
      borderRight: '1px solid var(--hairline)',
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px var(--space-regular)',
      display: 'flex'
    }
  }, /*#__PURE__*/React.createElement(FilterField, {
    value: filter,
    onChange: setFilter,
    placeholder: "\u8FC7\u6EE4\u5206\u652F\u4E0E\u6807\u7B7E"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)',
      overflowY: 'auto',
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "\u672C\u5730\u5206\u652F",
    action: /*#__PURE__*/React.createElement(Button, {
      variant: "borderless",
      size: "small",
      icon: "plus",
      title: "\u65B0\u5EFA\u5206\u652F"
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, ordered.length ? ordered.map(b => /*#__PURE__*/React.createElement(BranchRow, {
    key: b.name,
    name: b.name,
    isCurrent: b.isCurrent,
    ahead: b.ahead,
    behind: b.behind,
    gone: b.gone,
    selected: selected === b.name,
    onClick: () => onSelect(b.name),
    title: [b.name, b.upstream ? 'upstream：' + b.upstream : null, b.last ? '最新提交：' + b.last : null].filter(Boolean).join('\n')
  })) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px var(--space-regular)',
      font: 'var(--type-callout)',
      color: 'var(--ink-4)'
    }
  }, "\u6CA1\u6709\u5339\u914D\u7684\u5206\u652F")), /*#__PURE__*/React.createElement(Disclosure, {
    title: "\u8FDC\u7A0B\u5206\u652F",
    count: remotes.length,
    expanded: remoteOpen,
    onToggle: () => setRemoteOpen(!remoteOpen)
  }), remoteOpen ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, remotes.map(b => /*#__PURE__*/React.createElement(BranchRow, {
    key: b.name,
    name: b.name,
    isRemote: true,
    selected: selected === b.name,
    onClick: () => onSelect(b.name)
  }))) : null, /*#__PURE__*/React.createElement(Disclosure, {
    title: "\u6807\u7B7E",
    count: tags.length,
    expanded: tagsOpen,
    onToggle: () => setTagsOpen(!tagsOpen)
  }), tagsOpen ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 4
    }
  }, tags.map(t => /*#__PURE__*/React.createElement(TagRow, {
    key: t.name,
    name: t.name,
    annotated: t.annotated,
    title: t.message
  }))) : null));
}
Object.assign(window, {
  Sidebar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/Sidebar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/Timeline.jsx
try { (() => {
/* 时间线检查器（右侧 300pt）。
   不只记录「做了什么」，还留着「做之前长什么样」。点一条展开它等价的 git 命令。 */
const {
  Icon,
  ToolbarButton,
  Button,
  EmptyState
} = window.Git_c7d67c;
const HAZARD = {
  none: {
    icon: 'checkmark.circle',
    color: 'var(--ink-2)'
  },
  rewrite: {
    icon: 'pencil',
    color: 'var(--merge)'
  },
  discard: {
    icon: 'trash',
    color: 'var(--danger)'
  }
};
function EntryRow({
  entry
}) {
  const [open, setOpen] = React.useState(false);
  const [hover, setHover] = React.useState(false);
  const skin = HAZARD[entry.hazard] || HAZARD.none;
  return /*#__PURE__*/React.createElement("div", {
    onClick: () => setOpen(!open),
    title: "\u70B9\u51FB\u67E5\u770B\u7B49\u4EF7\u7684 git \u547D\u4EE4",
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 3,
      padding: '6px var(--space-loose)',
      background: hover ? 'var(--surface-hover)' : 'transparent'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: skin.icon,
    size: 12,
    color: entry.failed ? 'var(--warn)' : skin.color,
    style: {
      width: 14
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, entry.summary), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), hover && entry.canUndo ? /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small"
  }, "\u64A4\u9500") : null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-3)'
    }
  }, entry.time), entry.failed ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--warn)'
    }
  }, "\u5931\u8D25") : null, entry.canUndo ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 1,
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrow.uturn.backward",
    size: 9
  }), "\u53EF\u64A4\u9500") : null), open ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("code", {
    style: {
      display: 'block',
      padding: 6,
      borderRadius: 'var(--radius-small)',
      background: 'var(--surface-sunken)',
      font: 'var(--type-mono)',
      color: 'var(--ink-2)',
      whiteSpace: 'pre-wrap',
      overflowWrap: 'anywhere'
    }
  }, entry.cmd), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-2)'
    }
  }, entry.why)) : null);
}
function Timeline({
  timeline,
  onClose
}) {
  const [hovering, setHovering] = React.useState(null);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 'var(--col-inspector)',
      flex: '0 0 auto',
      display: 'flex',
      flexDirection: 'column',
      borderLeft: '1px solid var(--hairline)',
      background: 'var(--surface-app)',
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: 'var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock.arrow.circlepath",
    size: 14,
    color: "var(--brand)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-title)'
    }
  }, "\u65F6\u95F4\u7EBF"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "arrow.clockwise",
    title: "\u5237\u65B0\u65F6\u95F4\u7EBF"
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "xmark",
    title: "\u5173\u95ED",
    onClick: onClose
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--hairline)',
      overflowY: 'auto',
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 22,
      padding: '0 var(--space-loose)',
      display: 'flex',
      alignItems: 'center',
      background: 'var(--surface-sunken)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-secondary)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--ink-2)'
    }
  }, "\u64CD\u4F5C"), timeline.entries.map(e => /*#__PURE__*/React.createElement(EntryRow, {
    key: e.summary,
    entry: e
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 22,
      padding: '0 var(--space-loose)',
      display: 'flex',
      alignItems: 'center',
      background: 'var(--surface-sunken)',
      borderTop: '1px solid var(--hairline)',
      borderBottom: '1px solid var(--hairline)',
      font: 'var(--type-secondary)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--ink-2)'
    }
  }, "\u65F6\u95F4\u70B9"), timeline.snapshots.map(s => /*#__PURE__*/React.createElement("div", {
    key: s.summary,
    onMouseEnter: () => setHovering(s.summary),
    onMouseLeave: () => setHovering(null),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: '6px var(--space-loose)',
      background: hovering === s.summary ? 'var(--surface-hover)' : 'transparent'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "camera.fill",
    size: 12,
    color: "var(--accent)",
    style: {
      width: 14
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)'
    }
  }, s.summary), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-3)'
    }
  }, s.time)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), hovering === s.summary ? /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    size: "small"
  }, "\u6062\u590D") : null)), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 'var(--space-loose)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-caption)',
      color: 'var(--ink-3)'
    }
  }, "\u5FEB\u7167\u5B58\u5728 refs/yugit/*\uFF0C\u4E0D\u4F1A\u6DF7\u8FDB\u4F60\u7684\u5386\u53F2\u3002"))));
}
Object.assign(window, {
  Timeline
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/Timeline.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/Toolbar.jsx
try { (() => {
/* 窗口工具栏。红绿灯 + 仓库名/分支 + 远程三件套 + 更多。
   工具栏只留四项：可用宽度是被三栏分掉的剩余空间，比看上去窄得多。 */
const {
  ToolbarButton,
  TransferIndicator,
  Icon
} = window.Git_c7d67c;
function TrafficLights() {
  const dot = color => ({
    width: 12,
    height: 12,
    borderRadius: '50%',
    background: color
  });
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      paddingRight: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: dot('#FF5F57')
  }), /*#__PURE__*/React.createElement("span", {
    style: dot('#FEBC2E')
  }), /*#__PURE__*/React.createElement("span", {
    style: dot('#28C840')
  }));
}
function Toolbar({
  repo,
  branch,
  transferring,
  onFetch,
  onPull,
  onPush,
  onPalette,
  onTimeline,
  timelineOpen,
  onToggleSidebar,
  sidebarOpen
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-loose)',
      height: 'var(--toolbar-height)',
      padding: '0 var(--space-loose) 0 var(--traffic-light-inset)',
      background: 'var(--surface-sidebar)',
      backdropFilter: 'var(--blur-toolbar)',
      WebkitBackdropFilter: 'var(--blur-toolbar)',
      borderBottom: '1px solid var(--hairline)',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement(TrafficLights, null), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "sidebar.left",
    title: sidebarOpen ? '隐藏侧栏' : '显示侧栏',
    onClick: onToggleSidebar,
    active: sidebarOpen
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      paddingLeft: 'var(--space-regular)'
    }
  }, /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "chevron.left",
    title: "\u56DE\u5230\u6B22\u8FCE\u9875"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      lineHeight: 1.15
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--type-body)',
      fontWeight: 'var(--weight-semibold)'
    }
  }, repo), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      font: 'var(--type-secondary)',
      color: 'var(--ink-2)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrow.triangle.branch",
    size: 10,
    color: "var(--brand)"
  }), branch))), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), transferring ? /*#__PURE__*/React.createElement(TransferIndicator, {
    label: "\u5BF9\u8C61 1240 / 3877"
  }) : null, /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "arrow.down.circle",
    title: "\u4ECE\u8FDC\u7A0B\u62C9\u53D6\u5F15\u7528\u4E0E\u5BF9\u8C61\uFF0C\u4E0D\u6539\u52A8\u5DE5\u4F5C\u533A",
    disabled: transferring,
    onClick: onFetch
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "arrow.down.to.line",
    title: "\u62C9\u53D6\u5E76\u5408\u5E76\u5230\u5F53\u524D\u5206\u652F",
    disabled: transferring,
    onClick: onPull
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "arrow.up.to.line",
    title: "\u63A8\u9001\u5230 upstream",
    disabled: transferring,
    onClick: onPush
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      height: 20,
      background: 'var(--hairline)'
    }
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "clock.arrow.circlepath",
    title: "\u65F6\u95F4\u7EBF",
    active: timelineOpen,
    onClick: onTimeline
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "ellipsis.circle",
    title: "\u547D\u4EE4\u9762\u677F\u3001\u641C\u7D22\u3001\u65F6\u95F4\u7EBF\u3001\u5237\u65B0",
    onClick: onPalette
  }));
}
Object.assign(window, {
  Toolbar,
  TrafficLights
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/Toolbar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mac-app/data.js
try { (() => {
/* 演示数据。取自用户提供的截图：仓库 ai-cloud、当前分支 kino-aigc-chenya。
   只为让界面看起来是真的在用，不含任何逻辑。 */
window.YUGIT_FIXTURES = function () {
  const LANES = 6;
  const straight = skip => Array.from({
    length: LANES
  }, (_, i) => ({
    fromLane: i,
    toLane: i,
    colorIndex: i
  })).filter(l => !skip || !skip.includes(l.fromLane));
  const commits = [{
    hash: '6bb58134',
    subject: 'feat(积分安全): 赠送积分与年度限额',
    author: '后端陈亚',
    date: '4 个月前',
    day: '今天',
    lane: 0,
    links: straight()
  }, {
    hash: '685a312f',
    subject: 'S2 视频生成采用个人积分预扣',
    author: 'yangdong',
    date: '4 个月前',
    day: '今天',
    lane: 0,
    links: straight()
  }, {
    hash: '0e6c4a51',
    subject: 'S2 生成视频接口不获取团队 id',
    author: 'yangdong',
    date: '4 个月前',
    day: '今天',
    lane: 0,
    links: straight()
  }, {
    hash: '53d05aac',
    subject: 'S2 展示和生成视频接口改为个人维度',
    author: 'yangdong',
    date: '4 个月前',
    day: '昨天',
    lane: 0,
    links: straight()
  }, {
    hash: 'eeaf2817',
    subject: "Merge branch 'kino-aigc-new' into kino-aigc-new-seedace2.0",
    author: 'xiaolin@tvjoy.cn',
    date: '4 个月前',
    day: '昨天',
    lane: 2,
    isMerge: true,
    links: [...straight([3]), {
      fromLane: 3,
      toLane: 2,
      colorIndex: 3
    }],
    refs: [{
      kind: 'remote',
      name: 'origin/kino-aigc-new'
    }]
  }, {
    hash: '9eeb041c',
    subject: '2.0 跳转地址改成正式的',
    author: 'wangjun',
    date: '4 个月前',
    day: '昨天',
    lane: 1,
    links: straight()
  }, {
    hash: '01cd06d2',
    subject: '积分冻结参数转成大写',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年4月1日',
    lane: 1,
    links: straight()
  }, {
    hash: '6b054b88',
    subject: 'fix: 导航新增弹窗',
    author: '李泽林',
    date: '4 个月前',
    day: '2026年4月1日',
    lane: 1,
    isHead: true,
    links: straight().map(l => l.fromLane === 1 ? {
      ...l,
      isHead: true
    } : l),
    refs: [{
      kind: 'local',
      name: 'kino-aigc-chenya'
    }]
  }, {
    hash: '7dd04b9d',
    subject: 'fix:修改积分 bug',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年4月1日',
    lane: 1,
    links: straight()
  }, {
    hash: '608a57f4',
    subject: 'fix: 积分列表添加类型加两个字段',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年4月1日',
    lane: 1,
    links: straight()
  }, {
    hash: '083d3987',
    subject: '修改积分弹框异常问题',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年3月31日',
    lane: 1,
    links: straight()
  }, {
    hash: '4a16e473',
    subject: 'fix: 积分迁移入口放开，图片替换',
    author: '李泽林',
    date: '4 个月前',
    day: '2026年3月31日',
    lane: 1,
    links: straight()
  }, {
    hash: '5abaff13',
    subject: 'feat: 1.7 增加 kino claw (kino 爪)',
    author: '李泽林',
    date: '4 个月前',
    day: '2026年3月31日',
    lane: 1,
    links: straight()
  }, {
    hash: 'e6746c4c',
    subject: 'feat: 1.7 增加 ocp 模式 2.0',
    author: '李泽林',
    date: '4 个月前',
    day: '2026年3月31日',
    lane: 1,
    links: straight()
  }, {
    hash: '68309aa3',
    subject: 'feat:1、积分迁移模块对接完成',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年3月30日',
    lane: 1,
    links: straight()
  }, {
    hash: '10d81e19',
    subject: '积分迁移接口对接',
    author: 'wangjun',
    date: '4 个月前',
    day: '2026年3月30日',
    lane: 0,
    links: straight()
  }, {
    hash: 'aaf5bf33',
    subject: '增加 seedance2.0 视频模块与入口',
    author: 'xiaolin@tvjoy.cn',
    date: '4 个月前',
    day: '2026年3月30日',
    lane: 4,
    links: straight()
  }, {
    hash: '2d896a7d',
    subject: '积分迁移添加登录判断',
    author: 'xiaolin@tvjoy.cn',
    date: '4 个月前',
    day: '2026年3月30日',
    lane: 4,
    links: straight()
  }, {
    hash: '5c260aa1',
    subject: "Merge branch 'kino-aigc-new' into kino-aigc-new-dsc",
    author: 'xiaolin@tvjoy.cn',
    date: '4 个月前',
    day: '2026年3月29日',
    lane: 0,
    isMerge: true,
    links: [...straight([5]), {
      fromLane: 5,
      toLane: 0,
      colorIndex: 5
    }]
  }, {
    hash: '6566aa24',
    subject: "Merge branch 'kino-aigc-new-fcw'",
    author: 'xiaolin@tvjoy.cn',
    date: '4 个月前',
    day: '2026年3月29日',
    lane: 0,
    isMerge: true,
    links: straight()
  }];
  const localBranches = [{
    name: 'kino-aigc-chenya',
    isCurrent: true,
    upstream: 'origin/kino-aigc-chenya',
    last: 'fix: 导航新增弹窗'
  }, {
    name: 'kino-aigc-new',
    last: 'S2 视频生成采用个人积分预扣'
  }, {
    name: 'kino-aigc-new-dev',
    last: '积分迁移接口对接'
  }, {
    name: 'kino-aigc-ne…dev-TestDemo',
    last: '临时验证'
  }, {
    name: 'kino-aigc-new-fix',
    behind: 1,
    last: 'fix:修改积分 bug'
  }, {
    name: 'kino-aigc-new-test',
    last: '压测脚本'
  }, {
    name: 'master',
    ahead: 3,
    last: '发布 1.7'
  }, {
    name: 'feat/quota-gone',
    gone: true,
    last: 'upstream 已被删除'
  }];
  const remoteBranches = [{
    name: 'origin/detached'
  }, {
    name: 'origin/kino-aigc'
  }, {
    name: 'origin/kino-ai…base 基线版本'
  }, {
    name: 'origin/kino-aigc-chenya'
  }, {
    name: 'origin/kino-aigc-new'
  }, {
    name: 'origin/kino-aigc-new-144'
  }, {
    name: 'origin/kino-ai…-new-144-dsc'
  }, {
    name: 'origin/kino-aigc-new-V1.7.0'
  }, {
    name: 'origin/kino-aigc-new-cg'
  }, {
    name: 'origin/kino-aigc-new-dev'
  }];
  const tags = [{
    name: 'v1.7.0',
    annotated: true,
    message: '发布 1.7.0'
  }, {
    name: 'v2.0.0-rc1',
    annotated: true,
    message: '预发布'
  }, {
    name: 'tmp-before-rebase',
    annotated: false
  }];
  const changes = {
    conflicted: [{
      path: 'ai-web/frontend/src/store/modules/quota.ts',
      status: 'unmerged'
    }],
    staged: [{
      path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue',
      status: 'modified'
    }, {
      path: 'ai-web/frontend/src/locales/langs/zh-cn.ts',
      status: 'modified'
    }],
    unstaged: [{
      path: 'ai-web/frontend/src/router/elegant/routes.ts',
      status: 'modified'
    }, {
      path: 'ai-web/frontend/src/views/quota/migrate.vue',
      status: 'added'
    }, {
      path: 'ai-web/frontend/src/utils/legacy-quota.ts',
      status: 'deleted'
    }, {
      path: 'ai-web/frontend/.env.local',
      status: 'untracked'
    }]
  };
  const commitFiles = [{
    path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue',
    status: 'modified'
  }, {
    path: 'ai-web/frontend/src/locales/langs/zh-cn.ts',
    status: 'modified'
  }, {
    path: 'ai-web/frontend/src/router/elegant/routes.ts',
    status: 'modified'
  }];
  const seg = (text, syn, changed) => ({
    text,
    syn,
    changed
  });
  const diff = {
    path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue',
    added: 96,
    deleted: 5,
    hunks: [{
      header: '@@ -57,7 +57,7 @@',
      lines: [{
        kind: 'context',
        oldNumber: 57,
        newNumber: 57,
        segments: [seg('    <div style="')]
      }, {
        kind: 'context',
        oldNumber: 58,
        newNumber: 58,
        segments: [seg('      display', 'type'), seg(': flex;')]
      }, {
        kind: 'context',
        oldNumber: 59,
        newNumber: 59,
        segments: [seg('      padding', 'type'), seg(': '), seg('0 1rem', 'number'), seg(';')]
      }, {
        kind: 'deletion',
        oldNumber: 60,
        segments: [seg('      padding-bottom', 'type'), seg(': '), seg('1', 'number', true), seg('rem', 'number'), seg(';')]
      }, {
        kind: 'addition',
        newNumber: 60,
        segments: [seg('      padding-bottom', 'type'), seg(': '), seg('0.5', 'number', true), seg('rem', 'number'), seg(';')]
      }, {
        kind: 'context',
        oldNumber: 61,
        newNumber: 61,
        segments: [seg('      border-bottom', 'type'), seg(': '), seg('0.0625rem', 'number'), seg(' solid rgba('), seg('var(--base-border-color)', 'keyword'), seg(');')]
      }, {
        kind: 'context',
        oldNumber: 62,
        newNumber: 62,
        segments: [seg('      width', 'type'), seg(': '), seg('100%', 'number'), seg(';')]
      }]
    }, {
      header: '@@ -152,6 +152,5 @@',
      lines: [{
        kind: 'context',
        oldNumber: 152,
        newNumber: 152,
        segments: [seg('  '), seg('// 迁移入口，1.7 之后常驻', 'comment')]
      }, {
        kind: 'addition',
        newNumber: 160,
        segments: [seg('    <div style="')]
      }, {
        kind: 'addition',
        newNumber: 161,
        segments: [seg('      display', 'type'), seg(': flex;')]
      }, {
        kind: 'addition',
        newNumber: 162,
        segments: [seg('      padding', 'type'), seg(': '), seg('0 1rem', 'number'), seg(';')]
      }, {
        kind: 'addition',
        newNumber: 163,
        segments: [seg('      padding-bottom', 'type'), seg(': '), seg('0.5rem', 'number'), seg(';')]
      }, {
        kind: 'addition',
        newNumber: 164,
        segments: [seg('      align-items', 'type'), seg(': center;')]
      }, {
        kind: 'deletion',
        oldNumber: 158,
        segments: [seg('    '), seg('const', 'keyword'), seg(' legacy = '), seg('true', 'keyword'), seg(';')]
      }]
    }]
  };

  // 每条命令都带等价 git 命令：透明命令层，也是教学层
  const commands = [{
    icon: 'sparkles',
    title: 'AI 起草提交信息',
    hint: '根据暂存的改动生成，可直接编辑',
    cmd: ''
  }, {
    icon: 'square.stack.3d.up',
    title: '分批提交…',
    hint: '把一大坨改动拆成几次说得清楚的提交',
    cmd: 'git commit -m … （分多次）'
  }, {
    icon: 'checkmark.shield',
    title: '提交前自查',
    hint: '让 AI 通读暂存的改动，按风险分级',
    cmd: 'git diff --staged'
  }, {
    icon: 'arrow.triangle.merge',
    title: '整理提交历史…',
    hint: '拖动重排、squash、reword',
    cmd: 'git rebase -i HEAD~10'
  }, {
    icon: 'arrow.down.circle',
    title: '获取',
    hint: '只更新远程引用，不动工作区',
    cmd: 'git fetch --all --prune'
  }, {
    icon: 'arrow.up.to.line',
    title: '推送',
    hint: '推送到 upstream',
    cmd: 'git push origin kino-aigc-chenya'
  }, {
    icon: 'tray.and.arrow.down',
    title: '暂存改动到 stash',
    hint: '把当前改动收起来，稍后再拿回',
    cmd: 'git stash push -u'
  }, {
    icon: 'magnifyingglass',
    title: '搜索仓库',
    hint: '提交、信息、文件内容、分支',
    cmd: 'git log -S … / git grep'
  }, {
    icon: 'clock.arrow.circlepath',
    title: '时间线',
    hint: '所有写操作都在这里，可逐步撤销',
    cmd: 'git reflog / refs/yugit/*'
  }, {
    icon: 'square.split.2x1',
    title: '并行工作区…',
    hint: '同时开两个分支干活',
    cmd: 'git worktree add ../ai-cloud-fix'
  }, {
    icon: 'arrow.triangle.pull',
    title: '新建 Pull Request…',
    hint: 'GitHub / GitLab / Gitee',
    cmd: ''
  }, {
    icon: 'arrow.uturn.backward',
    title: '撤销上一步操作',
    hint: '退回到那一刻，当前状态会先存下来',
    cmd: 'git reset --hard refs/yugit/snapshot-…'
  }];
  const timeline = {
    entries: [{
      summary: '暂存 2 个文件',
      time: '3 分钟前',
      hazard: 'none',
      canUndo: true,
      cmd: 'git add -- kino-navigation.vue zh-cn.ts',
      why: '把改动放进索引，提交时只会带上索引里的内容。'
    }, {
      summary: '整理提交历史（rebase -i）',
      time: '18 分钟前',
      hazard: 'rewrite',
      canUndo: true,
      cmd: 'git rebase -i HEAD~6',
      why: '重写这 6 条提交，hash 全部会变；开始前已自动打 tag。'
    }, {
      summary: '丢弃 legacy-quota.ts 的改动',
      time: '1 小时前',
      hazard: 'discard',
      canUndo: true,
      cmd: 'git restore --worktree -- src/utils/legacy-quota.ts',
      why: '文件回到 HEAD 的内容，未提交的改动会消失 —— 已先拍快照。'
    }, {
      summary: '拉取 origin/kino-aigc-new',
      time: '2 小时前',
      hazard: 'none',
      canUndo: false,
      failed: true,
      cmd: 'git pull --ff-only',
      why: '本地有分叉，fast-forward 失败，什么都没改。'
    }],
    snapshots: [{
      summary: 'rebase 之前',
      time: '18 分钟前'
    }, {
      summary: '丢弃改动之前',
      time: '1 小时前'
    }]
  };
  return {
    LANES,
    commits,
    localBranches,
    remoteBranches,
    tags,
    changes,
    commitFiles,
    diff,
    commands,
    timeline
  };
}();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mac-app/data.js", error: String((e && e.message) || e) }); }

__ds_ns.CountPill = __ds_scope.CountPill;

__ds_ns.RefBadge = __ds_scope.RefBadge;

__ds_ns.StatusLetter = __ds_scope.StatusLetter;

__ds_ns.TrackingBadge = __ds_scope.TrackingBadge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.CopyButton = __ds_scope.CopyButton;

__ds_ns.FilterField = __ds_scope.FilterField;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.ToolbarButton = __ds_scope.ToolbarButton;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.DiffLine = __ds_scope.DiffLine;

__ds_ns.HunkHeader = __ds_scope.HunkHeader;

__ds_ns.SelectionBar = __ds_scope.SelectionBar;

__ds_ns.Banner = __ds_scope.Banner;

__ds_ns.EmptyState = __ds_scope.EmptyState;

__ds_ns.ExplanationPanel = __ds_scope.ExplanationPanel;

__ds_ns.HazardDialog = __ds_scope.HazardDialog;

__ds_ns.TransferIndicator = __ds_scope.TransferIndicator;

__ds_ns.GEOMETRY = __ds_scope.GEOMETRY;

__ds_ns.LANE_COUNT = __ds_scope.LANE_COUNT;

__ds_ns.LaneGraph = __ds_scope.LaneGraph;

__ds_ns.BranchRow = __ds_scope.BranchRow;

__ds_ns.CommitRow = __ds_scope.CommitRow;

__ds_ns.DayGroupRow = __ds_scope.DayGroupRow;

__ds_ns.DirectoryRow = __ds_scope.DirectoryRow;

__ds_ns.FileRow = __ds_scope.FileRow;

__ds_ns.SectionHeader = __ds_scope.SectionHeader;

__ds_ns.TagRow = __ds_scope.TagRow;

})();

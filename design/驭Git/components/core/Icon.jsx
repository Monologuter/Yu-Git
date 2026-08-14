import React from 'react';

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
export function Icon({ name, size = 14, color = 'currentColor', title, style, ...rest }) {
  const glyphs = (typeof window !== 'undefined' && window.YUGIT_SYMBOL_GLYPHS) || {};
  const glyph = glyphs[name];
  return (
    <span
      data-sf-symbol={name}
      title={title || name}
      aria-hidden={title ? undefined : true}
      style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        width: size, height: size, flex: '0 0 auto', color, ...style,
      }}
      {...rest}
    >
      {glyph ? (
        <span style={{ fontFamily: '"SF Pro Text", "SF Pro", -apple-system, system-ui', fontSize: size, lineHeight: 1 }}>{glyph}</span>
      ) : (
        <span style={{
          width: '76%', height: '76%', boxSizing: 'border-box',
          border: '1px dashed currentColor', borderRadius: Math.max(2, Math.round(size * 0.18)), opacity: 0.42,
        }} />
      )}
    </span>
  );
}

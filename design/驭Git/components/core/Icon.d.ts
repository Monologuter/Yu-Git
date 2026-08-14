/**
 * 一个 SF Symbol 的位置。name 与 Swift 侧 `Image(systemName:)` 完全一致，
 * 设计系统只承诺符号名，不分发图形；预览里画同尺寸占位框（无图片资源）。
 * 尺寸只用 11 / 14 / 16 / 56 四档，和字号档位对齐。
 */
export interface IconProps {
  /** SF Symbol 名，如 "arrow.triangle.branch"。清单见 Icon.prompt.md */
  name: string;
  /** 边长，默认 14（配 13pt 正文）。11 配 11pt 次要文字，16 配工具栏，56 只给空状态 */
  size?: number;
  /** 默认 currentColor —— 符号颜色应当跟着文字走 */
  color?: string;
  /** 有语义的符号要给 title；纯装饰的留空，会自动 aria-hidden（缺省时 title 落到符号名） */
  title?: string;
  style?: React.CSSProperties;
}
export function Icon(props: IconProps): JSX.Element;

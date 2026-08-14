/**
 * 图标。应用侧用 SF Symbols，这里用 Lucide 的同义图标替身（见 prompt.md 映射表）。
 * 尺寸只用 11 / 14 / 16 / 56 四档，和字号档位对齐。
 */
export interface IconProps {
  /** 文件名，不带扩展名，如 "git-branch"。对应 assets/icons/<name>.svg */
  name: string;
  /** 边长，默认 14（配 13pt 正文）。11 配 11pt 次要文字，16 配工具栏，56 只给空状态 */
  size?: number;
  /** 默认 currentColor —— 图标颜色应当跟着文字走 */
  color?: string;
  /** 有语义的图标要给 title；纯装饰的留空，会自动 aria-hidden */
  title?: string;
  style?: React.CSSProperties;
}
export function Icon(props: IconProps): JSX.Element;

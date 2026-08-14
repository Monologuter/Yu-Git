/**
 * 按钮。四种外观对应应用里真实用到的四类：默认动作、普通推按钮、
 * 行内无边框按钮、破坏性动作。

 */
export interface ButtonProps {
  children?: React.ReactNode;
  /** default=回车默认动作（强调色填充）｜bordered=普通推按钮｜borderless=行内文字按钮｜destructive=不可逆动作 */
  variant?: 'default' | 'bordered' | 'borderless' | 'destructive';
  /** small 20px（角标旁）｜regular 24px（默认）｜large 32px（欢迎页、sheet 主动作） */
  size?: 'small' | 'regular' | 'large';
  /** 图标名，见 Icon */
  icon?: string;
  disabled?: boolean;
  fullWidth?: boolean;
  onClick?: () => void;
  /** 悬停提示。应用里几乎每个按钮都有 .help()，这里同样别省 */
  title?: string;
  style?: React.CSSProperties;
}
export function Button(props: ButtonProps): JSX.Element;

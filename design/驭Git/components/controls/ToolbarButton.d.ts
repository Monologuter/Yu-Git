/** 工具栏图标按钮。只放图标，说明进 title —— 工具栏宽度是三栏之外的剩余空间。 */
export interface ToolbarButtonProps {
  icon: string;
  /** 必填。工具栏图标不自带文字，没有 title 就没人知道它做什么 */
  title: string;
  disabled?: boolean;
  /** 常驻打开的面板（如时间线检查器）用它表示当前是开着的 */
  active?: boolean;
  /** 右上角一个警示小点，用于「有东西需要处理」 */
  badge?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export function ToolbarButton(props: ToolbarButtonProps): JSX.Element;

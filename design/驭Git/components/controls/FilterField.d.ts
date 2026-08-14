/**
 * 列顶部的过滤输入框。11pt 文字，聚焦时描 2px 强调色。
 * 筛出来之后批量操作只作用于筛选结果 —— 这是它比搜索框更有用的地方。
 */
export interface FilterFieldProps {
  value: string;
  onChange?: (value: string) => void;
  /** 照实说筛什么：「过滤分支与标签」「过滤文件路径」「搜提交信息」 */
  placeholder?: string;
  autoFocus?: boolean;
  style?: React.CSSProperties;
}
export function FilterField(props: FilterFieldProps): JSX.Element;

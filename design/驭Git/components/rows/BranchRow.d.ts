/**
 * 侧栏分支行。当前分支加粗 + 品牌靛图标 + 左侧品牌色标记。
 * 远程分支换 `cloud` 符号，ahead/behind 在右端。
 */
export interface BranchRowProps {
  name: string;
  isRemote?: boolean;
  /** 当前 HEAD 所在的本地分支。列表里永远置顶 */
  isCurrent?: boolean;
  selected?: boolean;
  ahead?: number;
  behind?: number;
  gone?: boolean;
  /** 多行 tooltip：upstream、是否分叉、最新提交 */
  title?: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export function BranchRow(props: BranchRowProps): JSX.Element;

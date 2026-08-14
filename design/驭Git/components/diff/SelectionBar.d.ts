/** 行级暂存的操作条。只在有选中行时出现。 */
export interface SelectionBarProps {
  count: number;
  /** 已暂存的文件里要写「取消暂存选中的行」 */
  primaryLabel?: string;
  onApply?: () => void;
  onClear?: () => void;
  style?: React.CSSProperties;
}
export function SelectionBar(props: SelectionBarProps): JSX.Element;

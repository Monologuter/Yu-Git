/**
 * 分段控件（对应 .pickerStyle(.segmented)）。段数只到 2–3 个；再多就该换成侧栏或标签页。
 */
export interface SegmentItem {
  value: string;
  /** 标签自带状态：「变更 12」「变更 ⚠」—— 不用切过去才知道有没有改动 */
  label: React.ReactNode;
  title?: string;
}
export interface SegmentedControlProps {
  items: SegmentItem[];
  value: string;
  onChange?: (value: string) => void;
  style?: React.CSSProperties;
}
export function SegmentedControl(props: SegmentedControlProps): JSX.Element;

/**
 * 历史列表里的日期分组行（本设计系统新增，非原应用已有控件）。
 * 提交列表的节奏落点：每当日期变化插一条，粘在滚动顶部。
 */
export interface DayGroupRowProps {
  /** 「今天」「昨天」「2026年4月1日」—— 近三天用相对说法 */
  label: string;
  /** 这一天的提交数，可省 */
  count?: number;
  style?: React.CSSProperties;
}
export function DayGroupRow(props: DayGroupRowProps): JSX.Element;

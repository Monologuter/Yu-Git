/**
 * AI 中文解释面板（diff / commit / 冲突）。默认收起，展开才请求。
 * 那句「AI 生成的解释可能有误，请以代码为准」必须一直在 —— 不是免责声明，
 * 是让用户保持「以代码为准」的习惯。
 */
export interface ExplanationPanelProps {
  /** 「用中文讲讲这次 commit」「用中文讲讲这份改动」 */
  title: React.ReactNode;
  text?: React.ReactNode;
  loading?: boolean;
  /** 受控展开；不传则组件自己管 */
  expanded?: boolean;
  onToggle?: (expanded: boolean) => void;
  error?: React.ReactNode;
  style?: React.CSSProperties;
}
export function ExplanationPanel(props: ExplanationPanelProps): JSX.Element;

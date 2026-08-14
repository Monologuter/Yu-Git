/** 标题后的计数胶囊。tone="warn" 用于「有东西要处理」的计数（冲突数）。 */
export interface CountPillProps {
  children?: React.ReactNode;
  tone?: 'neutral' | 'warn';
  style?: React.CSSProperties;
}
export function CountPill(props: CountPillProps): JSX.Element;

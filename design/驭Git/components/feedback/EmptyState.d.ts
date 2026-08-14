/**
 * 空状态。标题说清情况，说明句给出下一步。
 * 图标落在品牌青的圆底里 —— 空状态是整屏唯一还能放品牌色的地方。
 */
export interface EmptyStateProps {
  /** 图标名。「工作区干净」用 circle-check，「没有匹配」用 search，「未选择内容」用 panel-right */
  icon?: string;
  title: React.ReactNode;
  /** 一句下一步。别写「暂无数据」这种什么都没说的话 */
  description?: React.ReactNode;
  action?: React.ReactNode;
  /** warn 用于「这个 diff 很大」这类需要用户决定的空状态 */
  tone?: 'brand' | 'warn';
  /** 窄栏里用 compact */
  compact?: boolean;
  style?: React.CSSProperties;
}
export function EmptyState(props: EmptyStateProps): JSX.Element;

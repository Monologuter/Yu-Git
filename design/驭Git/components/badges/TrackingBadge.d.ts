/** ahead / behind 指示，图标与数字间距 1px（紧凑角标）。gone 时改成警示三角。 */
export interface TrackingBadgeProps {
  ahead?: number;
  behind?: number;
  /** upstream 配置还在但远程分支已被删除 */
  gone?: boolean;
  emphasized?: boolean;
  style?: React.CSSProperties;
}
export function TrackingBadge(props: TrackingBadgeProps): JSX.Element;

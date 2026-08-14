/** commit 上的 ref 徽章：本地分支（品牌靛）、远程分支（灰）、tag（警示黄）。 */
export interface RefBadgeProps {
  kind?: 'local' | 'remote' | 'tag';
  children?: React.ReactNode;
  /** 所在行被选中时为 true，改用能压住强调色背景的前景色 */
  emphasized?: boolean;
  style?: React.CSSProperties;
}
export function RefBadge(props: RefBadgeProps): JSX.Element;

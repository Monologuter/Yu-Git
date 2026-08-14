/** hunk 头（@@ -161,7 +161,7 @@ …）。粘在滚动顶部，悬停出现「暂存此块」。 */
export interface HunkHeaderProps {
  header: string;
  action?: React.ReactNode;
  sticky?: boolean;
  style?: React.CSSProperties;
}
export function HunkHeader(props: HunkHeaderProps): JSX.Element;

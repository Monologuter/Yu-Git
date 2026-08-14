/** 侧栏 tag 行。annotated=false 时右侧标「轻量」。 */
export interface TagRowProps {
  name: string;
  annotated?: boolean;
  selected?: boolean;
  title?: string;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export function TagRow(props: TagRowProps): JSX.Element;

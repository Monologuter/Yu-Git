/**
 * diff 的一行。行号列宽按这个 diff 里最大的行号位数算（每位约 7px + 10px 内边距），
 * 固定宽度在小文件上很浪费 —— diff 面板本来就窄。
 */
export interface DiffSegment {
  text: string;
  /** 语法类别，只有五类 */
  syn?: 'keyword' | 'string' | 'comment' | 'number' | 'type' | 'plain';
  /** 这一段是行内真正变了的部分，叠一层更深的底色 */
  changed?: boolean;
}
export interface DiffLineProps {
  kind?: 'addition' | 'deletion' | 'context';
  oldNumber?: number | null;
  newNumber?: number | null;
  /** 纯文本内容；给了 segments 就用 segments */
  text?: string;
  segments?: DiffSegment[];
  selected?: boolean;
  /** 行号列宽度，同一个 diff 内必须一致 */
  gutterWidth?: number;
  /** 折行显示长行；折行时行号顶在第一行文字的基线上 */
  wrap?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export function DiffLine(props: DiffLineProps): JSX.Element;

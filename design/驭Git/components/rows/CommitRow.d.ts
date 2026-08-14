/**
 * 历史列表的一行：分支图 + 标题 +（hash · 作者 · 时间）。行高 44。

 */
export interface CommitRowProps {
  subject: string;
  /** 短 hash，等宽显示。完整 hash 交给复制按钮 */
  hash: string;
  author: string;
  /** 相对时间，短样式：「4 个月前」 */
  date: string;
  refs?: Array<{ kind?: 'local' | 'remote' | 'tag'; name: string }>;
  isMerge?: boolean;
  isHead?: boolean;
  /** 见 LaneGraph 的 GraphRow */
  graphRow?: import('../graph/LaneGraph').GraphRow;
  laneCount?: number;
  selected?: boolean;
  onClick?: () => void;
  style?: React.CSSProperties;
}
export function CommitRow(props: CommitRowProps): JSX.Element;

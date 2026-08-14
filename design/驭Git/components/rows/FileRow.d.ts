/**
 * 变更列表 / 提交详情里的一行文件。

 */
export interface FileRowProps {
  status: 'added' | 'modified' | 'deleted' | 'renamed' | 'copied' | 'untracked' | 'unmerged' | 'ignored' | 'typechange';
  /** 文件名（树模式）或完整路径（平铺模式） */
  name: string;
  /** 平铺模式下的所在目录；树模式留空 */
  directory?: string;
  selected?: boolean;
  /** 树模式的层级，每级缩进 12px */
  depth?: number;
  onClick?: () => void;
  /** 多行 tooltip：完整路径、原路径、相似度、submodule 状态、冲突提示 */
  title?: string;
  style?: React.CSSProperties;
}
export function FileRow(props: FileRowProps): JSX.Element;

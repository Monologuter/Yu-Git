/** 文件树里的目录行。单子目录链应在数据层合并（a/b/c 显示成一行）。 */
export interface DirectoryRowProps {
  /** 合并后的目录名，如 "src/main/java"。从头部截断 */
  name: string;
  /** 这个目录下的文件数 */
  count: number;
  collapsed?: boolean;
  depth?: number;
  /** 悬停出现的动作，通常是「暂存」/「取消」 */
  action?: React.ReactNode;
  onToggle?: () => void;
  title?: string;
  style?: React.CSSProperties;
}
export function DirectoryRow(props: DirectoryRowProps): JSX.Element;

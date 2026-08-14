/** 传输进度（获取 / 拉取 / 推送时出现在工具栏）。 */
export interface TransferIndicatorProps {
  /** 「对象 1240 / 3877」这类进度文本，等宽数字 */
  label?: React.ReactNode;
  style?: React.CSSProperties;
}
export function TransferIndicator(props: TransferIndicatorProps): JSX.Element;

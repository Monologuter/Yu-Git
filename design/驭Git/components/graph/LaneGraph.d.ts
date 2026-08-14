/**
 * 提交列表一行的分支图。线宽 2.5（HEAD 轨道 3.5），节点 4.5 环、中心挖空 2.6。

 */
export interface GraphLink {
  fromLane: number;
  toLane: number;
  /** 0–7，取模映射到 --lane-1…8 */
  colorIndex: number;
  /** HEAD 所在轨道加粗一档 */
  isHead?: boolean;
}
export interface GraphRow {
  nodeLane: number;
  colorIndex: number;
  links?: GraphLink[];
  /** 合并提交画实心点，普通提交画环 —— 形状区分，不只靠颜色 */
  isMerge?: boolean;
  /** HEAD 提交外面再套一圈品牌色细环 */
  isHead?: boolean;
}
export interface LaneGraphProps {
  row: GraphRow;
  /** 整个已加载历史的最大并行轨道数，不是当前一屏的 */
  laneCount?: number;
  /** 默认 14；轨道多时组件内部自动压缩，最窄 5 */
  laneGap?: number;
  height?: number;
  /** 行处于「选中且窗口活跃」时为 true：线与节点一律换成 --lane-on-emphasized */
  emphasized?: boolean;
  /** 节点挖空处填的颜色，必须等于行背景 */
  rowBackground?: string;
  style?: React.CSSProperties;
}
export function LaneGraph(props: LaneGraphProps): JSX.Element;
export function graphWidth(laneCount: number, laneGap?: number): number;
export function laneColor(index: number): string;
export const GEOMETRY: {
  laneGap: number; laneGapMin: number; widthMin: number; widthMax: number;
  nodeR: number; holeR: number; mergeR: number; headRingR: number;
};

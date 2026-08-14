import React from 'react';

/**
 * 一行的轨道与连线。整个客户端的门面就是它。
 *
 * 规则：
 * - 轨道间距对所有行必须一致，否则同一条轨道在相邻两行会错位、连不上。
 * - 轨道多到放不下时压缩间距（到 5 为止），而不是把图形区撑宽去挤标题。
 * - 选中行放弃区分轨道颜色，全部换成能压住强调色背景的前景色 ——
 *   丢掉的颜色只影响这一行，而这一行本来就靠背景高亮定位；
 *   「看不见」是更严重的问题。
 * - 节点靠形状区分：环 = 普通提交，实心点 = 合并，外圈细环 = HEAD。
 * - HEAD 外环用 --ink-1 深墨，不用品牌色：分支图是轨道色的地盘，品牌色进来只会
 *   多出一次「这是品牌还是某条分支」的判断。品牌色在侧栏、AI 入口、空状态出现。
 *
 * 几何量与 tokens/graph.css 一一对应（SVG 的 r/cx 属性吃不进 var()，
 * 所以这里是数字；线宽走 CSS 的 stroke-width，仍然读 token）。
 */
export const GEOMETRY = {
  laneGap: 14, laneGapMin: 5, widthMin: 24, widthMax: 84,
  nodeR: 4.5, holeR: 2.6, mergeR: 3.2, headRingR: 6.5,
};
export const LANE_COUNT = 8;
export const laneColor = (index) => 'var(--lane-' + ((index % LANE_COUNT) + 1) + ')';

export function graphWidth(laneCount, laneGap) {
  const lanes = Math.max(laneCount || 1, 1);
  const gap = laneGap || GEOMETRY.laneGap;
  return Math.min(Math.max(GEOMETRY.widthMin, lanes * gap), GEOMETRY.widthMax);
}

export function LaneGraph({
  row, laneCount = 1, laneGap = GEOMETRY.laneGap, height = 44,
  emphasized = false, rowBackground = 'var(--surface-app)', style,
}) {
  const gap = Math.max(GEOMETRY.laneGapMin, Math.min(laneGap, GEOMETRY.widthMax / Math.max(laneCount, 1)));
  const width = graphWidth(laneCount, gap);
  const centerX = (lane) => lane * gap + gap / 2;
  const middle = height / 2;
  const color = (index) => (emphasized ? 'var(--lane-on-emphasized)' : laneColor(index));

  return (
    <svg
      width={width} height={height} viewBox={'0 0 ' + width + ' ' + height}
      style={{ flex: '0 0 auto', display: 'block', overflow: 'hidden', ...style }}
    >
      {(row.links || []).map((link, i) => {
        const fromX = centerX(link.fromLane);
        const toX = centerX(link.toLane);
        const d = link.fromLane === link.toLane
          ? 'M ' + fromX + ' 0 L ' + fromX + ' ' + height
          : 'M ' + fromX + ' 0 C ' + fromX + ' ' + middle + ', ' + toX + ' ' + middle + ', ' + toX + ' ' + height;
        return (
          <path
            key={i} d={d} fill="none" strokeLinecap="round" stroke={color(link.colorIndex)}
            style={{ strokeWidth: link.isHead ? 'var(--graph-line-head)' : 'var(--graph-line)' }}
          />
        );
      })}

      {row.isHead && !emphasized ? (
        <circle
          cx={centerX(row.nodeLane)} cy={middle} r={GEOMETRY.headRingR}
          fill="none" stroke="var(--ink-1)" style={{ strokeWidth: 'var(--graph-head-ring-w)' }}
        />
      ) : null}

      {row.isMerge ? (
        <circle cx={centerX(row.nodeLane)} cy={middle} r={GEOMETRY.mergeR} fill={color(row.colorIndex)} />
      ) : (
        <React.Fragment>
          <circle cx={centerX(row.nodeLane)} cy={middle} r={GEOMETRY.nodeR} fill={color(row.colorIndex)} />
          <circle
            cx={centerX(row.nodeLane)} cy={middle} r={GEOMETRY.holeR}
            fill={emphasized ? 'var(--selection-bg)' : rowBackground}
          />
        </React.Fragment>
      )}
    </svg>
  );
}

/**
 * 跨栏横幅，用于「现在处在某个中间状态」：rebase 半途、有冲突、传输失败。

 */
export interface BannerProps {
  tone?: 'warn' | 'danger' | 'info' | 'ok';
  /** 一句说清现在是什么状态：「整理提交时遇到冲突」 */
  headline: React.ReactNode;
  /** 进度与下一步：「进行到第 2 / 5 条。冲突文件：a.swift。解决并暂存后点「继续」。」 */
  detail?: React.ReactNode;
  /** 出路做成按钮。破坏性的放左、需要前置条件的放右 */
  actions?: React.ReactNode;
  /** 兜底说明，通常是备份 tag 的位置 */
  footnote?: React.ReactNode;
  style?: React.CSSProperties;
}
export function Banner(props: BannerProps): JSX.Element;

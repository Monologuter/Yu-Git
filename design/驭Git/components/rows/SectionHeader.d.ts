/** 列表分组头。计数写在标题里（「未暂存（12）」），动作悬停才出现。 */
export interface SectionHeaderProps {
  title: React.ReactNode;
  count?: number;
  /** warn 用于冲突分组：那不是数量问题，是「先解决它」的性质问题 */
  tone?: 'neutral' | 'warn';
  /** 右侧动作，通常是 <Button variant="borderless" size="small"> */
  action?: React.ReactNode;
  sticky?: boolean;
  style?: React.CSSProperties;
}
export function SectionHeader(props: SectionHeaderProps): JSX.Element;

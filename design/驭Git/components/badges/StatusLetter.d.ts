/** 变更状态字母。A/M/D/R/C/?/!/· 各有固定字母与语义色，字母与颜色同时表达状态。 */
export interface StatusLetterProps {
  status: 'added' | 'modified' | 'deleted' | 'renamed' | 'copied' | 'untracked' | 'unmerged' | 'ignored' | 'typechange';
  emphasized?: boolean;
  style?: React.CSSProperties;
}
export function StatusLetter(props: StatusLetterProps): JSX.Element;

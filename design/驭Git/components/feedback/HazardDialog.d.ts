/**
 * 危险操作预警对话框（460 宽）。三个问题一次答完，并给出等价 git 命令。

 */
export interface HazardDialogProps {
  title: React.ReactNode;
  /** 会发生什么 —— 具体到文件数与内容，不要写「此操作可能有风险」 */
  whatHappens: React.ReactNode;
  /** 能不能撤销 */
  undoable?: React.ReactNode;
  /** 怎么撤销 —— 给出具体路径（时间线、备份 tag、reflog） */
  howToUndo?: React.ReactNode;
  /** 等价的 git 命令，原文照写 */
  command?: string;
  /** 确认按钮文案要重复动作本身：「丢弃这 3 个文件的改动」 */
  confirmLabel: React.ReactNode;
  onConfirm?: () => void;
  onCancel?: () => void;
  style?: React.CSSProperties;
}
export function HazardDialog(props: HazardDialogProps): JSX.Element;

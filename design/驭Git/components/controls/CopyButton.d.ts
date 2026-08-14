/** 复制按钮：点完切成对勾 1.5 秒。图标只做淡入淡出，不做位移动画。 */
export interface CopyButtonProps {
  /** 要复制的完整内容。界面上显示短 hash，复制的是 40 位全长 */
  text: string;
  title?: string;
  onCopy?: (text: string) => void;
  style?: React.CSSProperties;
}
export function CopyButton(props: CopyButtonProps): JSX.Element;

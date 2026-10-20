import type { WidgetProps } from "halo";

export default ({ screen }: WidgetProps) => {
  throw new Error(`render failure on ${screen.index}`);
};

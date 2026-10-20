import { Box, Surface, type WidgetProps } from "halo";
import { state } from "@/lib/shared";

export default ({ screen, props }: WidgetProps<{ label: string }>) => {
  state.mounted.push(`${props.label}@${screen.index}`);
  return (
    <Surface screen={screen} anchor={["top"]} size={{ width: 10, height: 10 }}>
      <Box />
    </Surface>
  );
};

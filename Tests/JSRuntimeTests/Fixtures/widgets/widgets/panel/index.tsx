import { Box, Surface, defineWidget } from "halo";
import { state } from "@/lib/shared";

export default defineWidget({
  props: { label: { type: "string", default: "none" } },
  render: ({ screen, props }) => {
    state.mounted.push(`${props.label}@${screen.index}`);
    return (
      <Surface screen={screen} anchor={["top"]} size={{ width: 10, height: 10 }}>
        <Box />
      </Surface>
    );
  },
});

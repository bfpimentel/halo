import { Box, Image, Surface, type WidgetProps } from "halo";
import { surface } from "@/demo/theme";

export default function Dock({ screen, props }: WidgetProps<{ apps?: string[] }>) {
  return (
    <Surface
      screen={screen}
      anchor={["left"]}
      margins={[0, 0, 0, 8]}
      size={{ width: 56, height: 164 }}
      layer="aboveMenu"
    >
      <Box
        style={{
          justify: "center",
          align: "center",
          gap: 8,
          background: surface,
          radius: 14,
        }}
      >
        {(props.apps ?? []).map((app) => (
          <Image app={app} size={40} />
        ))}
      </Box>
    </Surface>
  );
}

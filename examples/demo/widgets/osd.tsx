import { Box, Image, Surface, Text, type WidgetProps } from "halo";
import { signal } from "halo/signals";
import { foreground, muted, surface } from "@/demo/theme";

export default function Osd({ screen }: WidgetProps) {
  const visible = signal(true);
  setTimeout(() => visible.set(false), 3000);
  return (
    <Surface
      screen={screen}
      size={{ width: 180, height: 180 }}
      layer="overlay"
      visible={visible}
    >
      <Box
        style={{
          justify: "center",
          align: "center",
          gap: 14,
          background: surface,
          radius: 24,
        }}
      >
        <Image symbol="speaker.wave.2.fill" size={56} color={foreground} />
        <Text style={{ fontSize: 15, fontWeight: "medium", color: muted }}>halo</Text>
      </Box>
    </Surface>
  );
}

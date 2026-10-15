import { Box, Text, exec, poll } from "halo";
import { computed, signal, untrack } from "halo/signals";

const SAMPLES = 30;
const GRAPH_HEIGHT = 36;

/// 1-minute load average as a number, a color that follows it, and a rolling sparkline.
export function LoadGraph() {
  const raw = poll("sysctl -n vm.loadavg", 2000, "{ 0 0 0 }");
  const load = computed(
    () => Number(raw().replace(/[{}]/g, "").trim().split(/\s+/)[0]) || 0,
  );

  const cores = signal(1);
  exec("sysctl", ["-n", "hw.ncpu"]).then((result) =>
    cores.set(Number(result.stdout) || 1),
  );

  const history = signal<number[]>([]);
  setInterval(
    () => history.update((samples) => [...samples, untrack(load)].slice(-SAMPLES)),
    2000,
  );
  const peak = computed(() => Math.max(1, ...history()));

  const pressure = computed(() => load() / cores());
  const color = computed(() =>
    pressure() > 0.8 ? "#f38ba8" : pressure() > 0.5 ? "#f9e2af" : "#a6e3a1",
  );

  return (
    <Box style={{ padding: [12, 14], gap: 10, background: "#1e1e2ee0", radius: 16 }}>
      <Box style={{ flexDirection: "row", justify: "space-between", align: "center" }}>
        <Text style={{ color: "#9399b2", fontSize: 11, fontWeight: "semibold" }}>
          {() => `LOAD · ${cores()} CORES`}
        </Text>
        <Text style={{ color, fontSize: 20, fontWeight: "semibold" }}>
          {() => load().toFixed(2)}
        </Text>
      </Box>
      <Box style={{ flexDirection: "row", align: "end", gap: 2, height: GRAPH_HEIGHT }}>
        {() =>
          history().map((sample) => (
            <Box
              style={{
                width: 5,
                height: Math.max(2, (sample / peak()) * GRAPH_HEIGHT),
                background: color(),
                radius: 2,
              }}
            />
          ))
        }
      </Box>
    </Box>
  );
}

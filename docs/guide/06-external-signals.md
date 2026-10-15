# External signals

Push state into widgets from anywhere:

```bash
halo trigger music title="Song" artist="Band"
```

```tsx
import { externalSignal } from "halo/signals";

const music = externalSignal("music", { initial: { title: "", artist: "" } });
<Text>{() => `${music()?.title} — ${music()?.artist}`}</Text>;
```

- Payloads are string maps (`key=value`).
- `parse` turns a payload into any value; returning `undefined` ignores it.
- `hydrate` runs a shell command on load, so the value is right before the first trigger. Its result arrives as
  `{ stdout, stderr, code }`.
- The last payload survives reloads.

## AeroSpace

```tsx
import { aerospace } from "halo/aerospace";

const spaces = aerospace();
<Box style={{ flexDirection: "row", gap: 4 }}>
  {() =>
    spaces
      .on(screen)()
      .map((ws) => (
        <Text style={{ color: ws.focused ? "#89b4fa" : "#7f849c" }}>{ws.name}</Text>
      ))
  }
</Box>;
```

Add to `aerospace.toml`:

```toml
exec-on-workspace-change = ['/bin/bash', '-c',
  'halo trigger aerospace.workspace focused=$AEROSPACE_FOCUSED_WORKSPACE prev=$AEROSPACE_PREV_WORKSPACE']
on-focus-changed = ['exec-and-forget halo trigger aerospace.focus']
```

Reference: [`externalSignal`](../reference/halo-signals.html#externalSignal),
[`halo/aerospace`](../reference/halo-aerospace.html), [CLI](../cli.html).

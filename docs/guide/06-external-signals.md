# External signals

Push state into widgets from anywhere:

<video src="../assets/trigger.mp4" autoplay loop muted playsinline aria-label="Workspace pills following halo trigger commands"></video>

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

## Window managers

Workspace state comes from your window manager the same way: its hooks call `halo trigger`, and a `hydrate` query
fills the value in on load. The [AeroSpace example](../examples/aerospace.html) has the full setup, and the same
shape works for yabai or any WM with a CLI and change hooks.

Reference: [`externalSignal`](../reference/halo-signals.html#externalSignal), [CLI](../cli.html).

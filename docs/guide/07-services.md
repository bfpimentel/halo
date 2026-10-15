# Services

System state as signals, from `halo/services`. A service runs only while something reads it; reading
`battery.percent()` in a widget is all it takes.

![A status strip](../assets/status.png)

```tsx
import { audio, battery, frontApp, network, system } from "halo/services";

<Text>
  {() => `${battery.percent()}% · ${Math.round((system.cpu() ?? 0) * 100)}% CPU`}
</Text>;
```

| Service    | Values                                                                          | Updates                    |
| ---------- | ------------------------------------------------------------------------------- | -------------------------- |
| `battery`  | `present`, `percent`, `charging`, `source` (`ac`/`battery`), `minutesRemaining` | on power changes           |
| `audio`    | `volume` (0–1), `muted`, `device`                                               | on volume or device change |
| `network`  | `connected`, `type` (`wifi`, `ethernet`, …, `none`), `expensive`, `constrained` | on network change          |
| `frontApp` | `name`, `bundleId`, `pid`                                                       | on app switch              |
| `system`   | `cpu(ms?)`, `memory(ms?)`, `memoryUsed`, `memoryTotal`                          | every `ms` (default 2000)  |
| `clock`    | `format(pattern)`                                                               | every minute or second     |

Values are `undefined` until the first reading arrives.

## Actions

```tsx
audio.setVolume(0.4);
audio.toggleMuted();
<Box onScroll={({ dy }) => audio.setVolume((audio.volume() ?? 0) + dy * 0.01)} />;
```

`audio.volume()` is `undefined` for outputs with no software volume (many HDMI and DisplayPort monitors); setting it
returns `false` there.

## Notes

- `frontApp.bundleId()` works with `<Image app={…}>` for the app's icon.
- No Wi-Fi network name: it needs a Location permission halo can't ask for.
- `system` has no notification to follow, so it samples; pick the slowest interval you can live with.

Reference: [`halo/services`](../reference/halo-services.html). Full example:
[`examples/services`](https://github.com/bfpimentel/halo/blob/main/examples/services/main.tsx).

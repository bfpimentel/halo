# Services

System state as signals, from `halo/services`. A service runs only while something reads it; reading
`battery.percent()` in a widget is all it takes.

![A status strip](../assets/status.png)

```tsx
import {
  audio,
  battery,
  drag,
  frontApp,
  network,
  power,
  session,
  system,
} from "halo/services";

<Text>
  {() => `${battery.percent()}% · ${Math.round((system.cpu() ?? 0) * 100)}% CPU`}
</Text>;
```

| Service    | Values                                                                                               | Updates                    |
| ---------- | ---------------------------------------------------------------------------------------------------- | -------------------------- |
| `battery`  | `present`, `percent`, `charging`, `source` (`ac`/`battery`), `minutesRemaining`                      | on power changes           |
| `audio`    | `volume` (0–1), `muted`, `device`                                                                    | on volume or device change |
| `network`  | `connected`, `type` (`wifi`, `ethernet`, …, `none`), `expensive`, `constrained`                      | on network change          |
| `frontApp` | `name`, `bundleId`, `pid`                                                                            | on app switch              |
| `power`    | `lowPowerMode`, `thermal` (`nominal`, `fair`, `serious`, `critical`)                                 | on change                  |
| `session`  | `locked`, `displaysAsleep`, `lastWake` (ms; changes on every wake)                                   | on change                  |
| `drag`     | `active` (files are being dragged anywhere; true until the drop lands), `outgoing` (started in halo) | while the button is held   |
| `system`   | `cpu(ms?)`, `memory(ms?)`, `memoryUsed`, `memoryTotal`                                               | every `ms` (default 2000)  |
| `clock`    | `format(pattern)`                                                                                    | every minute or second     |

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
- No Wi-Fi network name: it needs a Location permission halo can't ask for. No Focus/Do Not Disturb either: macOS
  protects its state and the public API needs an authorization prompt.
- `session.locked()` relies on undocumented macOS signals, so it may stay `undefined` on future versions.
- Use `session.lastWake()` in an effect to refresh data after sleep.
- `system` has no notification to follow, so it samples; pick the slowest interval you can live with.

Reference: [`halo/services`](../reference/halo-services.html). Full example:
[`examples/services`](https://github.com/bfpimentel/halo/blob/main/examples/services/widgets/services.tsx).

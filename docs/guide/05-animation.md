# Animation

Changes are instant unless you ask. Core Animation does the work, off the main thread.

## Transitions

Animate style changes:

```tsx
<Box
  style={{
    scale: () => (hovered() ? 1.05 : 1),
    background: () => (active() ? "#89b4fa" : "#313244"),
    transition: { scale: { curve: "spring" }, background: 150, layout: 200 },
  }}
/>
```

Keys: any animatable property, `all`, or `layout` (position and size). Values: milliseconds or
`{ duration, curve, delay }`.

## Curves

`"linear"`, `"ease-in"`, `"ease-out"` (default), `"ease-in-out"`, cubic-bezier `[x1, y1, x2, y2]`, `"spring"`, or
`{ stiffness, damping, mass }`. Springs ignore `duration`.

## Enter and exit

```tsx
<Box
  enter={{ from: { opacity: 0, translateY: 8 }, duration: 200 }}
  exit={{ to: { opacity: 0, scale: 0.9 }, duration: 150 }}
/>
```

On elements, when they appear or are removed. On a `<Surface>`, every time it's shown or hidden; hiding waits for
the exit.

## Keyframes

```tsx
const spin = animate(
  icon,
  { rotate: [0, 360] },
  { duration: 1000, repeat: Infinity, curve: "linear" },
);
spin.cancel();
```

Options: `duration`, `curve`, `delay`, `repeat`, `alternate`, `offsets`, `fill`.

## Per frame

For anything else, JS runs on the display's refresh:

```tsx
const shown = tween(() => total(), { duration: 400 }); // a number that follows `total` smoothly
onFrame((time, dt) => {
  /* return false to stop */
});
```

Reference: [`animate`](../reference/halo.html#animate), [`Transitions`](../reference/halo.html#Transitions).

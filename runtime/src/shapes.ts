/** Path data for `<Shape>`, in its default 100×100 `viewBox`. */

const n = (value: number) => String(Math.round(value * 100) / 100);

/**
 * A full circle starting at the top, going clockwise: with `style.strokeEnd` (0–1) it's a progress ring.
 * `<Shape path={ring()} style={{ fill: "transparent", stroke: "#89b4fa", strokeWidth: 4, strokeEnd: 0.6 }} />`
 */
export function ring(): string {
  return "M 50 0 A 50 50 0 1 1 50 100 A 50 50 0 1 1 50 0";
}

/** Options for `sparkline`. */
export interface SparklineOptions {
  /** Bottom of the scale; defaults to the smallest value. */
  min?: number;
  /** Top of the scale; defaults to the largest value. */
  max?: number;
  /** Close the line down to the baseline, for a filled area. */
  area?: boolean;
}

/**
 * A line graph of `values`, left to right, spanning the 100×100 `viewBox`. Use it with `fit="stretch"`:
 * `<Shape path={() => sparkline(history())} fit="stretch" style={{ height: 24, fill: "transparent", stroke: "#a6e3a1" }} />`
 */
export function sparkline(values: number[], options: SparklineOptions = {}): string {
  if (values.length === 0) return "";
  const min = options.min ?? Math.min(...values);
  const max = options.max ?? Math.max(...values);
  const span = max - min || 1;
  const x = (index: number) =>
    values.length === 1 ? 0 : (index / (values.length - 1)) * 100;
  const y = (value: number) =>
    100 - ((Math.min(max, Math.max(min, value)) - min) / span) * 100;
  const points = values.map((value, index) => `${n(x(index))} ${n(y(value))}`);
  if (values.length === 1) points.push(`100 ${n(y(values[0] ?? 0))}`);
  const line = `M ${points.join(" L ")}`;
  return options.area ? `${line} L 100 100 L 0 100 Z` : line;
}

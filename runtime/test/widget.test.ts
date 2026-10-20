import { describe, expect, test } from "bun:test";
import {
  schemaRows,
  extraProps,
  parseSchemaEdit,
  setSchemaProp,
  stepNumber,
  type Config,
} from "halo/settings/model";
import { resolveProps, type NumberProp, type PropSchema } from "halo/widget";

const schema = {
  format: { type: "string", default: "HH:mm" },
  size: { type: "number", default: 28, min: 10, max: 96, step: 2 },
  accent: { type: "boolean", default: false },
  corner: { type: "select", options: ["left", "right"], default: "right" },
} satisfies PropSchema;

describe("widget props", () => {
  test("defaults fill in, invalid values fall back, unknown props pass through", () => {
    expect(resolveProps(schema, {})).toEqual({
      props: { format: "HH:mm", size: 28, accent: false, corner: "right" },
      errors: [],
    });
    const resolved = resolveProps(schema, {
      size: 200,
      accent: "yes",
      corner: "up",
      format: "HH:mm:ss",
      extra: 1,
    });
    expect(resolved.props).toEqual({
      format: "HH:mm:ss",
      size: 28,
      accent: false,
      corner: "right",
      extra: 1,
    });
    expect(resolved.errors).toEqual([
      "props.size must be at most 96, got 200; using 28",
      'props.accent must be true or false, got "yes"; using false',
      'props.corner must be one of "left", "right", got "up"; using "right"',
    ]);
  });

  test("editor rows, overrides and edits", () => {
    const rows = schemaRows(schema, { size: 40, extra: "x" });
    expect(rows.map((row) => [row.key, row.value, row.overridden])).toEqual([
      ["format", "HH:mm", false],
      ["size", 40, true],
      ["accent", false, false],
      ["corner", "right", false],
    ]);
    expect(extraProps(schema, { size: 40, extra: "x" })).toEqual({
      flat: [["extra", "x"]],
      nested: [],
    });

    const config: Config = { widgets: { a: { widget: "clock", props: { size: 40 } } } };
    expect(setSchemaProp(config, "a", "size", schema.size, 28).widgets.a).toEqual({
      widget: "clock",
    });
    expect(
      setSchemaProp(config, "a", "accent", schema.accent, true).widgets.a!.props,
    ).toEqual({
      size: 40,
      accent: true,
    });

    expect(parseSchemaEdit("50", schema.size)).toEqual({ value: 50 });
    expect(parseSchemaEdit("5", schema.size)).toEqual({ error: "at least 10" });
    expect(parseSchemaEdit("big", schema.size)).toHaveProperty("error");
    expect(parseSchemaEdit("HH", schema.format)).toEqual({ value: "HH" });

    const size: NumberProp = schema.size;
    expect(stepNumber(28, size, 1)).toBe(30);
    expect(stepNumber(95, size, 1)).toBe(96);
    expect(stepNumber(10, size, -1)).toBe(10);
    expect(stepNumber(0.1, { type: "number", default: 0, step: 0.2 }, 1)).toBe(0.3);
  });
});

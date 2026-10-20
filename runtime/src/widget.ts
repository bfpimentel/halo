import type { Element, WidgetProps } from "halo/components";

interface Described {
  /** Shown in `halo settings` instead of the prop's key. */
  label?: string;
  /** One line under the label in `halo settings`. */
  description?: string;
}

/** A text prop. */
export interface StringProp extends Described {
  type: "string";
  default: string;
}

/** A number prop, kept within `min`/`max` when given. */
export interface NumberProp extends Described {
  type: "number";
  default: number;
  min?: number;
  max?: number;
  /** How much `halo settings`' −/+ buttons change it. Default 1. */
  step?: number;
}

/** An on/off prop. */
export interface BooleanProp extends Described {
  type: "boolean";
  default: boolean;
}

/** One of a fixed list of strings. */
export interface SelectProp extends Described {
  type: "select";
  options: readonly string[];
  default: string;
}

/** One prop's type, default and how `halo settings` shows it. */
export type PropSpec = StringProp | NumberProp | BooleanProp | SelectProp;

/** A widget's props, by key. */
export type PropSchema = Record<string, PropSpec>;

/** The props a schema describes, with defaults applied. */
export type PropsOf<S extends PropSchema> = {
  [K in keyof S]: S[K] extends { type: "select"; options: readonly (infer O)[] }
    ? O
    : S[K] extends { type: "number" }
      ? number
      : S[K] extends { type: "boolean" }
        ? boolean
        : string;
};

/** A widget made with `defineWidget`: its render function plus the schema the host and `halo settings` read. */
export type Widget = ((input: WidgetProps) => Element) & { schema?: PropSchema };

/**
 * A widget with typed props: `halo.json` values are checked against `props` and missing ones take their defaults
 * before `render` runs, and `halo settings` shows a control per prop.
 */
export function defineWidget<const S extends PropSchema = {}>(definition: {
  /** The widget's props, in the order `halo settings` lists them. */
  props?: S;
  /** Runs once per screen the instance shows on. */
  render: (input: WidgetProps<PropsOf<S>>) => Element;
}): Widget {
  const widget = (input: WidgetProps) =>
    definition.render(input as WidgetProps<PropsOf<S>>);
  return Object.assign(widget, { schema: definition.props ?? {} });
}

function check(spec: PropSpec, value: unknown): string | undefined {
  switch (spec.type) {
    case "string":
      return typeof value === "string" ? undefined : "a string";
    case "boolean":
      return typeof value === "boolean" ? undefined : "true or false";
    case "number":
      if (typeof value !== "number" || !Number.isFinite(value)) return "a number";
      if (spec.min !== undefined && value < spec.min) return `at least ${spec.min}`;
      if (spec.max !== undefined && value > spec.max) return `at most ${spec.max}`;
      return undefined;
    case "select":
      return spec.options.includes(value as string)
        ? undefined
        : `one of ${spec.options.map((option) => JSON.stringify(option)).join(", ")}`;
  }
}

/**
 * `halo.json` props checked against a schema: missing and invalid values take their defaults (each invalid one
 * listed in `errors`); props the schema doesn't name pass through unchanged.
 */
export function resolveProps(
  schema: PropSchema,
  given: Record<string, unknown>,
): { props: Record<string, unknown>; errors: string[] } {
  const props: Record<string, unknown> = { ...given };
  const errors: string[] = [];
  for (const [key, spec] of Object.entries(schema)) {
    if (!(key in given)) {
      props[key] = spec.default;
      continue;
    }
    const problem = check(spec, given[key]);
    if (problem === undefined) continue;
    errors.push(
      `props.${key} must be ${problem}, got ${JSON.stringify(given[key])}; using ${JSON.stringify(spec.default)}`,
    );
    props[key] = spec.default;
  }
  return { props, errors };
}

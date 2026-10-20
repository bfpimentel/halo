import {
  resolveProps,
  type NumberProp,
  type PropSchema,
  type PropSpec,
} from "halo/widget";

/** Where an instance shows: every display, the menu-bar display, or 1-based display indices. */
export type Screens = "all" | "main" | number[];

/** A flat prop value the editor can change in place. */
export type Flat = string | number | boolean;

/** One instance in `halo.json`. */
export interface InstanceConfig {
  widget: string;
  screens?: Screens;
  props?: Record<string, unknown>;
}

/** The parts of `halo.json` the editor reads and writes. */
export interface Config {
  widgets: Record<string, InstanceConfig>;
}

/** Parses `halo.json`'s text; an error message instead of a config when it isn't one the editor can safely rewrite. */
export function parseConfig(text: string): { config: Config } | { error: string } {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (error) {
    return { error: `halo.json is not valid JSON: ${(error as Error).message}` };
  }
  if (!isObject(value) || !isObject(value.widgets))
    return { error: 'halo.json needs a "widgets" object' };
  for (const [name, instance] of Object.entries(value.widgets)) {
    if (!isObject(instance) || typeof instance.widget !== "string")
      return { error: `widgets.${name} needs a "widget"` };
  }
  return { config: value as unknown as Config };
}

/** `halo.json`'s text for a config: two-space indent and a trailing newline. */
export function serialize(config: Config): string {
  return JSON.stringify(config, null, 2) + "\n";
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Widget names in a `widgets/` listing: `<name>.tsx` files and folders holding an `index.tsx`. */
export function widgetNames(
  entries: { name: string; isDirectory: boolean }[],
  hasIndex: (folder: string) => boolean,
): string[] {
  const names = entries.flatMap((entry) => {
    if (entry.name.startsWith(".")) return [];
    if (entry.isDirectory) return hasIndex(entry.name) ? [entry.name] : [];
    return entry.name.endsWith(".tsx") ? [entry.name.slice(0, -4)] : [];
  });
  return [...new Set(names)].sort();
}

/** `base`, or `base-2`, `base-3`… if taken. */
export function uniqueName(config: Config, base: string): string {
  const stem = base.replace(/-\d+$/, "");
  if (!(base in config.widgets)) return base;
  for (let n = 2; ; n++) if (!(`${stem}-${n}` in config.widgets)) return `${stem}-${n}`;
}

/** Rebuilds `widgets` in order with `edit` applied, so renames keep their position. */
function mapInstances(
  config: Config,
  edit: (name: string, instance: InstanceConfig) => [string, InstanceConfig][],
): Config {
  const widgets: Record<string, InstanceConfig> = {};
  for (const [name, instance] of Object.entries(config.widgets))
    for (const [key, value] of edit(name, instance)) widgets[key] = value;
  return { ...config, widgets };
}

/** Appends an instance of `widget` (named after it, made unique). */
export function addInstance(
  config: Config,
  widget: string,
): { config: Config; name: string } {
  const name = uniqueName(config, widget);
  return {
    config: { ...config, widgets: { ...config.widgets, [name]: { widget } } },
    name,
  };
}

export function removeInstance(config: Config, name: string): Config {
  return mapInstances(config, (key, instance) => (key === name ? [] : [[key, instance]]));
}

/** Inserts a copy right after `name`. */
export function duplicateInstance(
  config: Config,
  name: string,
): { config: Config; name: string } {
  const copy = uniqueName(config, name);
  const next = mapInstances(config, (key, instance) =>
    key === name
      ? [
          [key, instance],
          [copy, structuredCopy(instance)],
        ]
      : [[key, instance]],
  );
  return { config: next, name: copy };
}

function structuredCopy<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

/** Renames an instance in place; an error when the name is empty or taken. */
export function renameInstance(
  config: Config,
  from: string,
  to: string,
): { config: Config } | { error: string } {
  const name = to.trim();
  if (name === from) return { config };
  if (name === "") return { error: "a name can't be empty" };
  if (name in config.widgets) return { error: `"${name}" is already used` };
  return {
    config: mapInstances(config, (key, instance) => [
      [key === from ? name : key, instance],
    ]),
  };
}

/** Applies `edit` to one instance. */
export function updateInstance(
  config: Config,
  name: string,
  edit: (instance: InstanceConfig) => InstanceConfig,
): Config {
  return mapInstances(config, (key, instance) => [
    [key, key === name ? edit(instance) : instance],
  ]);
}

/**
 * The screens after clicking a chip: "all" and "main" select themselves; a display index is toggled in the list
 * (from "all" or "main" it starts a new list), and emptying the list falls back to "all".
 */
export function toggleScreen(
  current: Screens | undefined,
  chip: "all" | "main" | number,
): Screens {
  if (chip === "all" || chip === "main") return chip;
  const list = Array.isArray(current) ? current : [];
  const next = list.includes(chip)
    ? list.filter((index) => index !== chip)
    : [...list, chip];
  return next.length === 0 ? "all" : next.sort((a, b) => a - b);
}

/** Whether a chip shows as selected. */
export function isSelected(
  current: Screens | undefined,
  chip: "all" | "main" | number,
): boolean {
  if (typeof chip === "number") return Array.isArray(current) && current.includes(chip);
  return (current ?? "all") === chip;
}

/** Props split into the ones edited in place and the nested ones left to `halo.json`. */
export function splitProps(props: Record<string, unknown> | undefined): {
  flat: [string, Flat][];
  nested: string[];
} {
  const flat: [string, Flat][] = [];
  const nested: string[] = [];
  for (const [key, value] of Object.entries(props ?? {})) {
    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean"
    )
      flat.push([key, value]);
    else nested.push(key);
  }
  return { flat, nested };
}

/** A typed edit of an existing prop, keeping its type; an error for a number that doesn't parse. */
export function parseEdit(
  text: string,
  previous: Flat,
): { value: Flat } | { error: string } {
  if (typeof previous === "number") {
    const value = Number(text.trim());
    return text.trim() !== "" && Number.isFinite(value)
      ? { value }
      : { error: `"${text}" is not a number` };
  }
  if (typeof previous === "boolean") return { value: text.trim() === "true" };
  return { value: text };
}

/** A new prop's value: `true`/`false` and numbers keep their type, anything else is a string. */
export function guessValue(text: string): Flat {
  const trimmed = text.trim();
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (trimmed !== "" && Number.isFinite(Number(trimmed))) return Number(trimmed);
  return text;
}

export function setProp(config: Config, name: string, key: string, value: Flat): Config {
  return updateInstance(config, name, (instance) => ({
    ...instance,
    props: { ...instance.props, [key]: value },
  }));
}

export function removeProp(config: Config, name: string, key: string): Config {
  return updateInstance(config, name, (instance) => {
    const props = { ...instance.props };
    delete props[key];
    const next: InstanceConfig = { ...instance, props };
    if (Object.keys(props).length === 0) delete next.props;
    return next;
  });
}

/** One schema prop as the editor shows it: its current value and whether `halo.json` overrides the default. */
export interface SchemaRow {
  key: string;
  spec: PropSpec;
  value: Flat;
  overridden: boolean;
}

/** A widget's schema props in schema order, valued from `halo.json` where valid, else their default. */
export function schemaRows(
  schema: PropSchema,
  props: Record<string, unknown> | undefined,
): SchemaRow[] {
  const { props: resolved } = resolveProps(schema, props ?? {});
  return Object.entries(schema).map(([key, spec]) => ({
    key,
    spec,
    value: resolved[key] as Flat,
    overridden: props !== undefined && key in props,
  }));
}

/** The instance's props the schema doesn't name, split like `splitProps`. */
export function extraProps(
  schema: PropSchema,
  props: Record<string, unknown> | undefined,
): ReturnType<typeof splitProps> {
  return splitProps(
    Object.fromEntries(Object.entries(props ?? {}).filter(([key]) => !(key in schema))),
  );
}

/** Sets a schema prop; setting it to its default removes the override, keeping `halo.json` minimal. */
export function setSchemaProp(
  config: Config,
  name: string,
  key: string,
  spec: PropSpec,
  value: Flat,
): Config {
  return value === spec.default
    ? removeProp(config, name, key)
    : setProp(config, name, key, value);
}

/** A typed edit of a schema text or number prop; numbers must parse and stay within `min`/`max`. */
export function parseSchemaEdit(
  text: string,
  spec: PropSpec,
): { value: Flat } | { error: string } {
  if (spec.type !== "number") return { value: text };
  const parsed = parseEdit(text, spec.default);
  if ("error" in parsed) return parsed;
  const value = parsed.value as number;
  if (spec.min !== undefined && value < spec.min)
    return { error: `at least ${spec.min}` };
  if (spec.max !== undefined && value > spec.max) return { error: `at most ${spec.max}` };
  return { value };
}

/** A number prop moved one `step` (default 1) up or down, kept within `min`/`max`. */
export function stepNumber(value: number, spec: NumberProp, direction: 1 | -1): number {
  const next = Math.round((value + direction * (spec.step ?? 1)) * 1e6) / 1e6;
  return Math.min(spec.max ?? Infinity, Math.max(spec.min ?? -Infinity, next));
}

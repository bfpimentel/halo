import {
  Box,
  Image,
  Input,
  Surface,
  Text,
  readDir,
  screens,
  watchFile,
  writeFile,
  type Element,
  type WidgetProps,
} from "halo";
import { close } from "halo/internal";
import { computed, effect, signal } from "halo/signals";
import {
  addInstance,
  duplicateInstance,
  guessValue,
  isSelected,
  parseConfig,
  extraProps,
  parseEdit,
  parseSchemaEdit,
  removeInstance,
  removeProp,
  renameInstance,
  serialize,
  schemaRows,
  setProp,
  setSchemaProp,
  splitProps,
  stepNumber,
  toggleScreen,
  updateInstance,
  widgetNames,
  type Config,
  type Flat,
  type SchemaRow,
} from "halo/settings/model";
import type { PropSchema } from "halo/widget";

const card = "#1e1e2e";
const raised = "#313244";
const line = "#ffffff14";
const foreground = "#cdd6f4";
const muted = "#7f849c";
const accent = "#89b4fa";
const danger = "#f38ba8";
const onAccent = "#1e1e2e";

const schemas = signal<Record<string, PropSchema>>({});
globalThis.__halo.onSchemas = (json) =>
  schemas.set(JSON.parse(json) as Record<string, PropSchema>);

function Label(props: { children: string }) {
  return (
    <Text style={{ fontSize: 11, fontWeight: "semibold", color: muted }}>
      {props.children.toUpperCase()}
    </Text>
  );
}

function Chip(props: {
  label?: string;
  selected?: () => boolean;
  symbol?: string;
  tone?: "accent" | "danger";
  onClick: () => void;
}) {
  const hovered = signal(false);
  const on = () => props.selected?.() ?? false;
  const tint = props.tone === "danger" ? danger : accent;
  return (
    <Box
      style={{
        flexDirection: "row",
        align: "center",
        gap: 5,
        padding: [4, 9],
        radius: 6,
        background: () => (on() ? tint : hovered() ? "#45475a" : raised),
        transition: { background: 90 },
      }}
      onHover={hovered.set}
      onClick={props.onClick}
    >
      {props.symbol ? (
        <Image
          symbol={props.symbol}
          size={11}
          color={() => (on() ? onAccent : props.tone === "danger" ? danger : foreground)}
        />
      ) : null}
      {props.label ? (
        <Text
          style={{
            fontSize: 12,
            fontWeight: "medium",
            color: () =>
              on() ? onAccent : props.tone === "danger" ? danger : foreground,
          }}
        >
          {props.label}
        </Text>
      ) : null}
    </Box>
  );
}

/** A text field that commits on Enter or Tab. */
function Field(props: {
  value: string;
  placeholder?: string;
  width?: number;
  onCommit: (value: string) => void;
}) {
  const draft = signal(props.value);
  return (
    <Box
      style={{
        width: props.width,
        grow: props.width === undefined ? 1 : 0,
        shrink: 1,
        padding: [4, 8],
        radius: 6,
        background: raised,
      }}
    >
      <Input
        value={draft}
        placeholder={props.placeholder}
        style={{ fontSize: 13, color: foreground }}
        onInput={draft.set}
        onSubmit={(value) => props.onCommit(value)}
        onKeyDown={({ key }) => {
          if (key === "Tab") return (props.onCommit(draft()), false);
          if (key === "Escape") return (close(), true);
        }}
      />
    </Box>
  );
}

function Toggle(props: { value: boolean; onChange: (value: boolean) => void }) {
  return (
    <Box
      style={{
        width: 34,
        height: 20,
        padding: 2,
        radius: 10,
        align: props.value ? "end" : "start",
        background: props.value ? accent : raised,
      }}
      onClick={() => props.onChange(!props.value)}
    >
      <Box style={{ width: 16, height: 16, radius: 8, background: foreground }} />
    </Box>
  );
}

/** The `halo settings` editor: every instance in halo.json, its screens and its flat props, saved on each change. */
export default function Settings({ screen }: WidgetProps) {
  const text = watchFile("halo.json");
  const parsed = computed(() => {
    const contents = text();
    return contents === undefined
      ? { error: "no halo.json in the config folder yet; run `halo init`" }
      : parseConfig(contents);
  });
  const config = computed(() => {
    const result = parsed();
    return "config" in result ? result.config : undefined;
  });
  const selected = signal<string | undefined>(undefined);
  const current = computed(() => {
    const widgets = config()?.widgets ?? {};
    const name = selected();
    return name !== undefined && name in widgets ? name : Object.keys(widgets)[0];
  });
  const status = signal<string | undefined>(undefined);
  const available = signal<string[]>([]);

  effect(() => {
    text();
    readDir("widgets")
      .then(async (entries) => {
        const folders = entries.filter((entry) => entry.isDirectory);
        const withIndex = new Set<string>();
        await Promise.all(
          folders.map((folder) =>
            readDir(`widgets/${folder.name}`)
              .then((inside) => {
                if (inside.some((entry) => entry.name === "index.tsx"))
                  withIndex.add(folder.name);
              })
              .catch(() => {}),
          ),
        );
        available.set(widgetNames(entries, (folder) => withIndex.has(folder)));
      })
      .catch(() => available.set([]));
  });

  const save = (next: Config) => {
    status.set(undefined);
    writeFile("halo.json", serialize(next)).catch((error: Error) =>
      status.set(error.message),
    );
  };
  const edit = (change: (config: Config) => Config) => {
    const now = config();
    if (now) save(change(now));
  };

  const instanceList = () => {
    const widgets = config()?.widgets ?? {};
    return Object.entries(widgets).map(([name, instance]) => {
      const hovered = signal(false);
      const active = () => current() === name;
      return (
        <Box
          style={{
            padding: [6, 10],
            gap: 1,
            radius: 7,
            background: () =>
              active() ? "#89b4fa2e" : hovered() ? "#ffffff0d" : "transparent",
            transition: { background: 90 },
          }}
          onHover={hovered.set}
          onClick={() => selected.set(name)}
        >
          <Text style={{ fontSize: 13, fontWeight: "medium", color: foreground }}>
            {name}
          </Text>
          <Text style={{ fontSize: 11, color: muted }}>{instance.widget}</Text>
        </Box>
      );
    });
  };

  const addList = () =>
    available().map((widget) => (
      <Chip
        label={widget}
        symbol="plus"
        onClick={() =>
          edit((now) => {
            const added = addInstance(now, widget);
            selected.set(added.name);
            return added.config;
          })
        }
      />
    ));

  const screenChips = (name: string) => {
    const instance = config()?.widgets[name];
    const chips: ["all" | "main" | number, string][] = [
      ["all", "All"],
      ["main", "Main"],
      ...screens().map((each): [number, string] => [
        each.index,
        `${each.index} · ${each.name}`,
      ]),
    ];
    return chips.map(([chip, label]) => (
      <Chip
        label={label}
        selected={() => isSelected(instance?.screens, chip)}
        onClick={() =>
          edit((now) =>
            updateInstance(now, name, (it) => ({
              ...it,
              screens: toggleScreen(it.screens, chip),
            })),
          )
        }
      />
    ));
  };

  const propRow = (name: string, key: string, value: Flat): Element => (
    <Box style={{ flexDirection: "row", align: "center", gap: 8 }}>
      <Box style={{ width: 110 }}>
        <Text style={{ fontSize: 13, color: muted }}>{key}</Text>
      </Box>
      {typeof value === "boolean" ? (
        <Box style={{ grow: 1 }}>
          <Toggle
            value={value}
            onChange={(next) => edit((now) => setProp(now, name, key, next))}
          />
        </Box>
      ) : (
        <Field
          value={String(value)}
          onCommit={(input) => {
            const result = parseEdit(input, value);
            if ("error" in result) return status.set(result.error);
            edit((now) => setProp(now, name, key, result.value));
          }}
        />
      )}
      <Chip
        symbol="xmark"
        tone="danger"
        onClick={() => edit((now) => removeProp(now, name, key))}
      />
    </Box>
  );

  const schemaRow = (name: string, row: SchemaRow): Element => {
    const { key, spec, value } = row;
    const set = (next: Flat) => edit((now) => setSchemaProp(now, name, key, spec, next));
    let control: Element;
    if (spec.type === "boolean")
      control = <Toggle value={value as boolean} onChange={set} />;
    else if (spec.type === "select")
      control = (
        <Box style={{ flexDirection: "row", gap: 6 }}>
          {spec.options.map((option) => (
            <Chip
              label={option}
              selected={() => value === option}
              onClick={() => set(option)}
            />
          ))}
        </Box>
      );
    else {
      const field = (
        <Field
          value={String(value)}
          width={spec.type === "number" ? 90 : undefined}
          onCommit={(input) => {
            const result = parseSchemaEdit(input, spec);
            if ("error" in result)
              return status.set(`${spec.label ?? key}: ${result.error}`);
            set(result.value);
          }}
        />
      );
      control =
        spec.type === "number" ? (
          <Box style={{ flexDirection: "row", align: "center", gap: 6 }}>
            <Chip
              symbol="minus"
              onClick={() => set(stepNumber(value as number, spec, -1))}
            />
            {field}
            <Chip
              symbol="plus"
              onClick={() => set(stepNumber(value as number, spec, 1))}
            />
          </Box>
        ) : (
          field
        );
    }
    return (
      <Box style={{ flexDirection: "row", align: "center", gap: 8 }}>
        <Box style={{ width: 140, gap: 1 }}>
          <Text style={{ fontSize: 13, color: foreground }}>{spec.label ?? key}</Text>
          {spec.description ? (
            <Text style={{ fontSize: 11, color: muted, lines: 0 }}>
              {spec.description}
            </Text>
          ) : null}
        </Box>
        <Box style={{ grow: 1, shrink: 1, flexDirection: "row", align: "center" }}>
          {control}
        </Box>
        {row.overridden ? (
          <Chip
            symbol="arrow.uturn.backward"
            onClick={() => edit((now) => removeProp(now, name, key))}
          />
        ) : null}
      </Box>
    );
  };

  const newProp = (name: string) => {
    const key = signal("");
    return (
      <Box style={{ flexDirection: "row", align: "center", gap: 8 }}>
        <Field value="" placeholder="new prop" width={110} onCommit={key.set} />
        <Field
          value=""
          placeholder="value, then Enter"
          onCommit={(input) => {
            const prop = key().trim();
            if (prop === "")
              return status.set("type the prop's name first (Enter or Tab)");
            edit((now) => setProp(now, name, prop, guessValue(input)));
          }}
        />
      </Box>
    );
  };

  const details = () => {
    const name = current();
    const instance = name === undefined ? undefined : config()?.widgets[name];
    if (name === undefined || !instance)
      return (
        <Text style={{ fontSize: 13, color: muted }}>
          No widgets yet: add one from the list on the left.
        </Text>
      );
    const schema = schemas()[instance.widget];
    const { flat, nested } = schema
      ? extraProps(schema, instance.props)
      : splitProps(instance.props);
    return (
      <Box style={{ gap: 14 }}>
        <Box style={{ gap: 6 }}>
          <Label>Name</Label>
          <Box style={{ flexDirection: "row", align: "center", gap: 8 }}>
            <Field
              value={name}
              width={240}
              onCommit={(input) => {
                const now = config();
                if (!now) return;
                const result = renameInstance(now, name, input);
                if ("error" in result) return status.set(result.error);
                selected.set(input.trim());
                save(result.config);
              }}
            />
            <Text
              style={{ fontSize: 12, color: muted }}
            >{`widgets/${instance.widget}`}</Text>
          </Box>
        </Box>
        <Box style={{ gap: 6 }}>
          <Label>Screens</Label>
          <Box style={{ flexDirection: "row", gap: 6 }}>{screenChips(name)}</Box>
        </Box>
        <Box style={{ gap: 6 }}>
          <Label>Props</Label>
          {schema
            ? schemaRows(schema, instance.props).map((row) => schemaRow(name, row))
            : null}
          {schema && flat.length + nested.length > 0 ? (
            <Text style={{ fontSize: 11, color: muted }}>
              {"Not in the widget's schema:"}
            </Text>
          ) : null}
          {flat.map(([key, value]) => propRow(name, key, value))}
          {nested.map((key) => (
            <Text
              style={{ fontSize: 12, color: muted }}
            >{`${key}: edit in halo.json`}</Text>
          ))}
          {schema ? null : newProp(name)}
        </Box>
        <Box style={{ flexDirection: "row", gap: 6, padding: [4, 0, 0, 0] }}>
          <Chip
            label="Duplicate"
            symbol="plus.square.on.square"
            onClick={() =>
              edit((now) => {
                const copy = duplicateInstance(now, name);
                selected.set(copy.name);
                return copy.config;
              })
            }
          />
          <Chip
            label="Remove"
            symbol="trash"
            tone="danger"
            onClick={() => edit((now) => removeInstance(now, name))}
          />
        </Box>
      </Box>
    );
  };

  return (
    <Surface
      screen={screen}
      layer="overlay"
      input="keyboard"
      onKeyDown={({ key }) => (key === "Escape" ? (close(), true) : false)}
      enter={{
        from: { opacity: 0, scale: 0.97 },
        curve: { stiffness: 380, damping: 30 },
      }}
    >
      <Box
        style={{
          width: 700,
          padding: 16,
          gap: 14,
          background: card,
          radius: 16,
          borderWidth: 1,
          borderColor: "#ffffff1a",
        }}
      >
        <Box style={{ flexDirection: "row", align: "center", gap: 10 }}>
          <Image symbol="slider.horizontal.3" size={16} color={accent} />
          <Box style={{ grow: 1 }}>
            <Text style={{ fontSize: 15, fontWeight: "semibold", color: foreground }}>
              halo settings
            </Text>
          </Box>
          <Chip label="Close" symbol="xmark" onClick={close} />
        </Box>
        <Box style={{ height: 1, background: line }} />
        {() => {
          const result = parsed();
          if ("error" in result)
            return (
              <Text style={{ fontSize: 13, color: danger, lines: 0 }}>
                {result.error}
              </Text>
            );
          return (
            <Box style={{ flexDirection: "row", gap: 16 }}>
              <Box style={{ width: 190, gap: 10 }}>
                <Box style={{ gap: 2 }}>{instanceList}</Box>
                <Box style={{ height: 1, background: line }} />
                <Label>Add</Label>
                <Box style={{ gap: 4, align: "start" }}>{addList}</Box>
              </Box>
              <Box style={{ width: 1, background: line }} />
              <Box style={{ grow: 1, shrink: 1 }}>{details}</Box>
            </Box>
          );
        }}
        <Text
          style={{ fontSize: 11, color: () => (status() ? danger : muted), lines: 0 }}
        >
          {() =>
            status() ??
            "Changes save to halo.json as you make them. Enter applies a field; Esc closes."
          }
        </Text>
      </Box>
    </Surface>
  );
}

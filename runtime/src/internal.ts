import { PerScreen } from "halo/components";
import { installGlobals, mount as mountApp, reportError } from "halo/host";
import { native, type ScreenInfo } from "halo/native";
import { beginScope, root } from "halo/reactive";
import { resolveProps, type PropSchema, type Widget } from "halo/widget";

installGlobals();
const scope = beginScope();

/** One `halo.json` instance, as the host's generated entry describes it. */
export interface Instance {
  name: string;
  /** The widget file's name in `widgets/`. */
  widget: string;
  /** Evaluates the widget's module (lazily, so a module that throws only takes down its own instances). */
  load: () => unknown;
  screens: "all" | "main" | number[];
  props: Record<string, unknown>;
}

function shows(screens: Instance["screens"], screen: ScreenInfo): boolean {
  if (screens === "all") return true;
  if (screens === "main") return screen.index === 1;
  return screens.includes(screen.index);
}

function mountInstance(instance: Instance, schemas: Record<string, PropSchema>): void {
  const label = `widget "${instance.name}"`;
  let widget: unknown;
  try {
    widget = instance.load();
  } catch (error) {
    return reportError(error, label);
  }
  if (typeof widget !== "function")
    return reportError(new Error("its file has no default export function"), label);
  const schema = (widget as Widget).schema;
  let props = instance.props;
  if (schema) {
    schemas[instance.widget] = schema;
    const resolved = resolveProps(schema, instance.props);
    for (const error of resolved.errors) reportError(new Error(error), label);
    props = resolved.props;
  }
  root(() =>
    PerScreen({
      children: (screen) => {
        if (!shows(instance.screens, screen)) return null;
        try {
          return (widget as Widget)({ screen, props });
        } catch (error) {
          reportError(error, label);
          return null;
        }
      },
    }),
  );
}

export function mount(instances: Instance[]): void {
  const schemas: Record<string, PropSchema> = {};
  mountApp(scope, () =>
    instances.forEach((instance) => mountInstance(instance, schemas)),
  );
  native.publishSchemas(JSON.stringify(schemas));
}

/** Closes a built-in app's runtime (no-op in user configs). */
export function close(): void {
  native.close();
}

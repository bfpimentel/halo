import { PerScreen, type Element, type WidgetProps } from "halo/components";
import { installGlobals, mount as mountApp, reportError } from "halo/host";
import { native, type ScreenInfo } from "halo/native";
import { beginScope, root } from "halo/reactive";

installGlobals();
const scope = beginScope();

type Widget = (props: WidgetProps) => Element;

/** One `halo.json` instance, as the host's generated entry describes it. */
export interface Instance {
  name: string;
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

function mountInstance(instance: Instance): void {
  const label = `widget "${instance.name}"`;
  let widget: unknown;
  try {
    widget = instance.load();
  } catch (error) {
    return reportError(error, label);
  }
  if (typeof widget !== "function")
    return reportError(new Error("its file has no default export function"), label);
  root(() =>
    PerScreen({
      children: (screen) => {
        if (!shows(instance.screens, screen)) return null;
        try {
          return (widget as Widget)({ screen, props: instance.props });
        } catch (error) {
          reportError(error, label);
          return null;
        }
      },
    }),
  );
}

export function mount(instances: Instance[]): void {
  mountApp(scope, () => instances.forEach(mountInstance));
}

/** Closes a built-in app's runtime (no-op in user configs). */
export function close(): void {
  native.close();
}

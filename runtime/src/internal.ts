import { installGlobals, mount as mountApp } from "halo/host";
import { beginScope } from "halo/reactive";

installGlobals();
const scope = beginScope();

export function mount(app: unknown): void {
  mountApp(scope, app);
}

import { installGlobals, mount as mountApp } from "./host";
import { beginScope } from "./reactive";

installGlobals();
const scope = beginScope();

export function mount(app: unknown): void {
  mountApp(scope, app);
}

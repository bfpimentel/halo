export type Accessor<T> = () => T;

export interface Signal<T> extends Accessor<T> {
  set(value: T): void;
  update(fn: (value: T) => T): void;
}

type Equals<T> = false | ((a: T, b: T) => boolean);

const CLEAN = 0;
const CHECK = 1;
const DIRTY = 2;

interface Source {
  observers: Set<Computation<unknown>>;
}

class Owner {
  children: Owner[] = [];
  cleanups: (() => void)[] = [];
  disposed = false;

  constructor(public parent: Owner | null) {
    parent?.children.push(this);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.disposeContents();
    if (this.parent) {
      const index = this.parent.children.indexOf(this);
      if (index >= 0) this.parent.children.splice(index, 1);
    }
  }

  protected disposeContents(): void {
    const children = this.children;
    this.children = [];
    for (let i = children.length - 1; i >= 0; i--) {
      children[i].parent = null;
      children[i].dispose();
    }
    const cleanups = this.cleanups;
    this.cleanups = [];
    for (let i = cleanups.length - 1; i >= 0; i--) {
      try {
        cleanups[i]();
      } catch (error) {
        reportError(error);
      }
    }
  }
}

class SignalNode<T> implements Source {
  observers = new Set<Computation<unknown>>();

  constructor(
    public value: T,
    private equals: Equals<T>,
  ) {}

  read(): T {
    track(this);
    return this.value;
  }

  write(value: T): void {
    if (this.equals && this.equals(this.value, value)) return;
    this.value = value;
    for (const observer of this.observers) observer.mark(DIRTY);
    flush();
  }
}

/// Glitch-free push/pull: writes mark observers DIRTY and their dependents CHECK;
/// a CHECK computation re-runs only if one of its memo sources actually changed.
class Computation<T> extends Owner implements Source {
  observers = new Set<Computation<unknown>>();
  sources = new Set<Source>();
  state = DIRTY;
  value: T | undefined;
  private hasValue = false;

  constructor(
    private fn: (previous: T | undefined) => T,
    private isEffect: boolean,
    private equals: Equals<T>,
  ) {
    super(currentOwner);
  }

  mark(state: number): void {
    if (this.state >= state) return;
    const wasClean = this.state === CLEAN;
    this.state = state;
    if (!wasClean) return;
    if (this.isEffect) queue.push(this);
    for (const observer of this.observers) observer.mark(CHECK);
  }

  update(): void {
    if (this.disposed) return;
    if (this.state === CHECK) {
      for (const source of this.sources) {
        if (source instanceof Computation) {
          source.update();
          if (this.state === DIRTY) break;
        }
      }
    }
    if (this.state === DIRTY) this.run();
    this.state = CLEAN;
  }

  read(): T {
    this.update();
    track(this);
    return this.value as T;
  }

  private run(): void {
    this.disposeContents();
    this.unlinkSources();
    const previous = enter(this, this as Computation<unknown>);
    try {
      const value = this.fn(this.value);
      const unchanged =
        this.hasValue && this.equals && this.equals(this.value as T, value);
      if (!this.isEffect && !unchanged) {
        for (const observer of this.observers) observer.state = DIRTY;
      }
      this.value = value;
      this.hasValue = true;
    } catch (error) {
      reportError(error);
    } finally {
      enter(...previous);
    }
  }

  private unlinkSources(): void {
    for (const source of this.sources) source.observers.delete(this);
    this.sources.clear();
  }

  override dispose(): void {
    if (this.disposed) return;
    super.dispose();
    this.unlinkSources();
  }
}

let currentOwner: Owner | null = null;
let listener: Computation<unknown> | null = null;
let batchDepth = 0;
let flushing = false;
let queue: Computation<unknown>[] = [];
let errorHandler: (error: unknown) => void = (error) => console.error(error);

/// Makes `owner`/`tracking` current and returns the previous pair, for restoring afterwards.
function enter(
  owner: Owner | null,
  tracking: Computation<unknown> | null,
): [Owner | null, Computation<unknown> | null] {
  const previous: [Owner | null, Computation<unknown> | null] = [currentOwner, listener];
  currentOwner = owner;
  listener = tracking;
  return previous;
}

function track(source: Source): void {
  if (!listener) return;
  listener.sources.add(source);
  source.observers.add(listener);
}

function reportError(error: unknown): void {
  errorHandler(error);
}

function flush(): void {
  if (batchDepth > 0 || flushing) return;
  flushing = true;
  try {
    for (let rounds = 0; queue.length > 0; rounds++) {
      if (rounds > 100) {
        queue = [];
        throw new Error(
          "signals: effects kept re-triggering each other (more than 100 rounds)",
        );
      }
      const pending = queue;
      queue = [];
      for (const computation of pending) computation.update();
    }
  } finally {
    flushing = false;
  }
}

export function signal<T>(initial: T, options?: { equals?: Equals<T> }): Signal<T> {
  const node = new SignalNode(initial, options?.equals ?? Object.is);
  const accessor = (() => node.read()) as Signal<T>;
  accessor.set = (value) => node.write(value);
  accessor.update = (fn) => node.write(fn(node.value));
  return accessor;
}

export function computed<T>(fn: () => T, options?: { equals?: Equals<T> }): Accessor<T> {
  const computation = new Computation<T>(fn, false, options?.equals ?? Object.is);
  return () => computation.read();
}

export function effect(fn: () => void): void {
  const computation = new Computation<void>(fn, true, false);
  computation.update();
}

export function batch<T>(fn: () => T): T {
  batchDepth++;
  try {
    return fn();
  } finally {
    batchDepth--;
    flush();
  }
}

export function untrack<T>(fn: () => T): T {
  const previous = listener;
  listener = null;
  try {
    return fn();
  } finally {
    listener = previous;
  }
}

export function onCleanup(fn: () => void): void {
  currentOwner?.cleanups.push(fn);
}

/// Runs `fn` in a new ownership scope, disposed with its parent or by calling `dispose`.
export function root<T>(fn: (dispose: () => void) => T): T {
  const owner = new Owner(currentOwner);
  const previousOwner = currentOwner;
  const previousListener = listener;
  currentOwner = owner;
  listener = null;
  try {
    return fn(() => owner.dispose());
  } finally {
    currentOwner = previousOwner;
    listener = previousListener;
  }
}

export type OwnerHandle = Owner;

export function getOwner(): OwnerHandle | null {
  return currentOwner;
}

export function runWithOwner<T>(owner: OwnerHandle | null, fn: () => T): T {
  const previousOwner = currentOwner;
  const previousListener = listener;
  currentOwner = owner;
  listener = null;
  try {
    return fn();
  } finally {
    currentOwner = previousOwner;
    listener = previousListener;
  }
}

/// Makes a new scope current until `endScope`: module-level code then has an owner like component code does.
export function beginScope(): OwnerHandle {
  currentOwner = new Owner(null);
  return currentOwner;
}

export function endScope(): void {
  currentOwner = null;
}

export function setErrorHandler(handler: (error: unknown) => void): void {
  errorHandler = handler;
}

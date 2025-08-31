# XState v5 Guide & Project Patterns

A comprehensive reference for XState v5, tailored for this project. This guide covers core concepts and established patterns used in our `authMachine` and `navigationMachine`.

## 1. Introduction: Why State Machines?

A **state machine** is a mathematical model of computation. In our application, it's a powerful pattern for managing complex UI state in a predictable, robust, and visualizable way. It helps us slay bugs like race conditions, infinite loops, and impossible states.

- **Finite States**: The system can only be in one of a finite number of predefined states (e.g., `idle`, `loading`, `success`, `error`).
- **Events**: States change only in response to explicit events (e.g., `FETCH`, `RETRY`, `LOGIN`).
- **Transitions**: The rules that govern how the machine moves from one state to another based on an event.
- **Predictability**: Given the current state and an event, the next state is always predictable.

## 2. Core Building Blocks

### 2.1. States

A **state** describes the system's current status.

#### Simple States

The most basic type of state.
`"idle"`, `"loading"`, `"success"`.

#### Parent (Compound) States

States can be nested. A parent state contains its own child states, which are only active when the parent is. This helps group related logic.

- **`initial`**: A parent state **must** define which child state is entered by default.
- **Event Bubbling**: Events are handled by the deepest child state first. If it doesn't handle the event, it "bubbles" up to its parent.

**Use Case**: The `authMachine` has an `idle_authenticated` parent state with child states for different authenticated activities. A `LOGOUT` event can be defined on the parent and it will be valid for all child states.

```typescript
// authMachine
states: {
  idle_authenticated: {
    // This event is handled here, regardless of which child state is active.
    on: { LOGOUT: 'loggingOut' },
    initial: 'stable',
    states: {
      stable: { /* ... */ },
      revalidating: { /* ... */ }
    }
  }
}
```

#### Final States

A state that, once entered, signifies the machine (or its parent state) has completed its work.

- **`type: 'final'`**: The syntax for a final state.
- **`onDone`**: When a child state reaches a final state, the parent state takes its `onDone` transition.
- **`output`**: A final state can produce output data, which is passed to the `onDone` action.

**Use Case**: An actor that fetches data can have a `success` final state. The parent machine can then use `onDone` to process the fetched data.

```typescript
// An invoked actor for fetching data
fetchUser: {
  initial: 'fetching',
  states: {
    fetching: {
      invoke: {
        src: 'fetchUserActor',
        onDone: { 
          target: 'success', 
          actions: assign({ user: ({ event }) => event.output }) 
        }
      }
    },
    success: { type: 'final' }
  }
}
```

### 2.2. Context

The "extended state" of the machine. While states represent *what* mode the system is in (qualitative), `context` stores *quantitative* data (strings, numbers, objects).

- **Immutable**: Context should be treated as read-only. It is only updated via the `assign` action.
- **`context` property**: Defines the initial context of the machine.

**Use Case**: The `navigationMachine` stores `pathname`, `isAuthenticated`, `isAuthLoading`, etc., in its context. This allows it to make decisions based on a complete snapshot of the application's routing and auth state.

```typescript
// navigationMachine
context: {
  pathname: '/',
  isAuthenticated: false,
  isAuthLoading: true,
  // ... and other relevant state
}
```

### 2.3. Events

Plain JavaScript objects that trigger state transitions. They represent *what happened*, not *how it should be handled*.

- **`type` property**: A string that uniquely identifies the event.
- **Payload**: Events can carry data.

**Use Case**: The `NavigationManager` gathers state from various Jotai atoms and sends a single, comprehensive `CONTEXT_UPDATED` event to the `navigationMachine` on every render.

```typescript
// Sending an event to a jotai-xstate machine
const [, send] = useAtom(myMachineAtom);
send({ type: 'MY_EVENT', payload: { id: 123 } });
```

### 2.4. Transitions

The rules that define how a machine moves from a source state to a target state in response to an event.

- **`on` property**: An object within a state definition where keys are event types and values are transition configurations.
- **`target`**: The state to transition to.
  - `'stateName'`: Absolute target (from the root).
  - `'.childState'`: Relative target (from the parent).
- **`always`**: An "eventless" transition that is taken immediately if its `guard` condition is met.

**Use Case**: The `navigationMachine`'s central `evaluating` state uses a series of `always` transitions with guards to deterministically decide the next state (e.g., `redirectingToLogin`, `idle`) based on the current context.

```typescript
// navigationMachine
evaluating: {
  always: [
    { target: 'redirectingToLogin', guard: 'shouldRedirectToLogin' },
    { target: 'redirectingFromLogin', guard: 'shouldRedirectFromLogin' },
    { target: 'idle' } // Default transition if no guards pass
  ]
}
```

### 2.5. Actions

Fire-and-forget side effects that occur upon entering/exiting a state or during a transition.

- **`entry`**: Actions to run when entering a state.
- **`exit`**: Actions to run when exiting a state.
- **`actions`**: Actions to run during a transition.
- **`assign`**: A special action creator for updating the machine's `context`.

**Use Case**: The `authMachine` uses an `assign` action in the `onDone` handler of its `loggingIn` state to merge the returned `AuthStatus` into its context.

```typescript
// authMachine
onDone: {
  target: 'idle_authenticated',
  actions: assign(({ event }) => {
    // event.output contains the data returned from the invoked actor
    const { user, isAuthenticated } = event.output;
    return {
      user,
      isAuthenticated,
      errorCode: null,
    };
  })
}
```

### 2.6. Guards (Conditions)

Functions that return `true` or `false`, determining whether a transition should be taken. They allow a single event to cause different transitions based on `context` or event data.

- **`guard` property**: The condition for a transition.
- **Pure Functions**: Guards should be pure functions without side effects.

**Use Case**: The `navigationMachine` is replete with guards. `shouldRedirectToLogin` checks if the user is unauthenticated on a private path while not in the middle of an auth check.

```typescript
// In the machine's `guards` implementation
shouldRedirectToLogin: ({ context }) =>
  !context.isAuthenticated &&
  !context.isAuthLoading &&
  !isPublicPath(context.pathname)
```

## 3. Asynchronous Operations (Actors)

XState uses the **actor model** to manage async operations like promises, callbacks, or even other machines.

- **`invoke`**: The property on a state that defines an actor to be run.
- **`src`**: The source of the actor (a promise-returning function, another machine, etc.).
- **`onDone` / `onError`**: Transitions taken when the actor succeeds or fails. The result/error is available on `event.output` / `event.error`.

**Use Case**: The `authMachine`'s `initial_refreshing` state invokes the `refreshToken` actor. The `onDone` handler processes the successful refresh, while `onError` transitions to a failed state. This encapsulates the entire async flow within the state machine.

```typescript
// authMachine
initial_refreshing: {
  invoke: {
    id: 'refreshToken',
    src: 'refreshTokenActor',

    onDone: {
      target: 'evaluating_initial_session',
      actions: assign({
        // ... update context with result from event.output
      })
    },
    onError: {
      target: 'idle_unauthenticated',
      actions: assign({
        // ... update context with error code
      })
    }
  }
}
```

## 4. Querying State in Components

Inside your components, you can inspect the machine's current state snapshot to render the correct UI.

- **`state.matches(value)`**: Checks if the current state value is or is a child of `value`.
- **`state.hasTag(tag)`**: Checks if the current active state has a given `tag`. **This is preferred** as it's more resilient to refactoring the machine's structure.
- **`state.can(event)`**: Checks if an event would cause a transition. Useful for disabling buttons.

**Use Case**: The `PageContentGuard` uses `!navState.matches('idle')` to show a loading spinner while the `navigationMachine` is busy, preventing a flash of content.

## 5. TypeScript & XState v5 (`typescript: ^5.8.2`)

XState v5 has first-class TypeScript support. The `setup()` function is the key to a fully typed machine.

```typescript
import { setup, assign, fromPromise, createActor } from 'xstate';
import type { SnapshotFrom } from 'xstate';

// Define all your types first
interface MachineContext {
  user: User | null;
  retries: number;
}
type MachineEvents = 
  | { type: 'LOGIN', user: User }
  | { type: 'LOGOUT' };

export const authMachine = setup({
  // Define actor logic
  actors: {
    loginActor: fromPromise<AuthStatus, { user: User }>(
      async ({ input }) => { /* ... */ }
    )
  },
  // Define actions
  actions: {
    incrementRetries: assign({ retries: ({ context }) => context.retries + 1 })
  },
  // Define guards
  guards: {
    hasUser: ({ context }) => context.user !== null
  },
  // Define all types for the machine
  types: {
    context: {} as MachineContext,
    events: {} as MachineEvents,
  }
}).createMachine({
  /* ... your machine config ... */
});

// To get the type of the machine's state snapshot in a component
type AuthMachineSnapshot = SnapshotFrom<typeof authMachine>;
```

## 6. Project-Specific Patterns

### The `Manager` Component Pattern

Our `NavigationManager` is a critical pattern. It's a client-side component that:
1.  Subscribes to all relevant Jotai atoms (`pathname`, `authStatus`, etc.).
2.  On every render, it gathers their current values.
3.  It sends a single `CONTEXT_UPDATED` event to the state machine with the fresh data.
4.  It subscribes to the machine's state and executes any commanded side-effects (e.g., `router.push(path)`).

This decouples the state machine from the rest of the application. The machine is a pure function, and the `Manager` is its interface to the outside world.

### The "Scribe" Effect Pattern

The `authMachineScribeEffectAtom` and `navMachineScribeEffectAtom` are `useEffect`-like atoms that listen for changes in their respective machine's state. When a change occurs, they record a detailed entry in the `eventJournalAtom`. This provides an invaluable, chronological log of all state transitions for debugging in the `StateInspector`.

# STATBUS Authentication & Navigation State Architecture

This document provides a formal overview of the state management architecture for authentication and navigation. The system is built on **XState** and **Jotai** to create a robust, predictable, and debuggable state layer that is resilient to race conditions, especially those introduced by React Strict Mode and Next.js Fast Refresh.

## 1. High-Level Architecture

The architecture is composed of three distinct state machines, each with a single, clear responsibility. They communicate indirectly by observing state changes in shared Jotai atoms. A dedicated `NavigationManager` component acts as the orchestrator.

1.  **`authMachine`**: The single source of truth for **authentication state**. It handles all API interactions (login, logout, refresh, status checks) and manages the user's session.
2.  **`navigationMachine`**: The single source of truth for **programmatic navigation**. It decides *when* and *where* to redirect the user based on application state, but does not perform the navigation itself.
3.  **`loginUiMachine`**: A purely presentational machine that controls the UI of the `/login` page, deciding whether to show the form or a loading spinner.
4.  **`NavigationManager`**: A React component that acts as the "glue". It subscribes to Jotai atoms, feeds context into the `navigationMachine`, and executes the side-effects (e.g., redirects) that the machine commands.

This separation of concerns is the cornerstone of the system's robustness.

---

## 2. The `authMachine`

-   **File**: `app/src/atoms/auth-machine.ts`
-   **Purpose**: To be the sole manager of the user's authentication lifecycle.

### Key States

-   `uninitialized`: The initial state, waiting for the REST client to be ready.
-   `checking`: The initial, one-time check of the user's auth status when the app loads.
-   `evaluating_initial_session`: A transient state that decides where to go after the initial check.
-   `initial_refreshing`: Handles a required token refresh on the initial application load.
-   `idle_authenticated`: The main, stable state for an authenticated user. It is a parent state with its own internal states:
    -   `stable`: The default "happy path". The user is authenticated and no action is pending. **Tagged `auth-stable`**.
    -   `revalidating`: A non-blocking, proactive check of the auth status is in progress.
    -   `background_refreshing`: A non-blocking token refresh is in progress.
-   `idle_unauthenticated`: The main, stable state for a logged-out user. **Tagged `auth-stable`**.
-   `loggingIn`: A transient state while the login API call is in flight.
-   `loggingOut`: A transient state while the logout API call is in flight.

### Key Concepts & Patterns

-   **Actors for Async Operations**: All API calls (`checkAuthStatus`, `refreshToken`, `login`, `logout`) are encapsulated in XState **actors**. This cleanly separates the asynchronous logic from the state machine's declarative structure.
-   **State Tagging for UI Stability**:
    -   **`ui-authenticated` tag**: Applied to all states where the user should be *considered* authenticated from a UI perspective (e.g., `idle_authenticated`, `checking`, `initial_refreshing`). This is the key to preventing UI "flaps" (e.g., a protected layout unmounting and remounting) during background token refreshes. The `isUserConsideredAuthenticatedForUIAtom` is derived from this tag.
    -   **`auth-stable` tag**: Applied only to the final, settled states (`idle_authenticated.stable` and `idle_unauthenticated`). This provides a clear signal to the `navigationMachine` that it is safe to make a routing decision.

---

## 3. The `navigationMachine`

-   **File**: `app/src/atoms/navigation-machine.ts`
-   **Purpose**: To be the sole decider for all application-level redirects.

### Key States

-   `booting`: The initial state, immediately transitions to `evaluating`.
-   `evaluating`: The central decision-making hub. It's a transient state that uses a series of guarded, `always` transitions to immediately move to the correct state based on the current application context.
-   `idle`: The stable "happy path" state. No navigation is required. **Tagged `stable`**.
-   `savingPathForLoginRedirect`: An intermediate state that commands the `NavigationManager` to save the user's current URL before redirecting them to login.
-   `redirectingToLogin`: Commands a redirect to `/login`. Waits for the `pathname` to confirm the redirect is complete.
-   `redirectingFromLogin`: Commands a redirect away from `/login` for an authenticated user. Waits for the `pathname` to change before proceeding.
-   `redirectingToSetup`: Commands a redirect to a required setup page (e.g., `/getting-started`).
-   `cleanupAfterRedirect`: A state that runs after a successful login redirect to clean up temporary state, like `lastKnownPathBeforeAuthChangeAtom`.

### Key Concepts & Patterns

-   **Idempotency and Resilience to Fast Refresh**: The machine is designed to be robust against rapid re-renders.
    1.  The `NavigationManager` sends a `CONTEXT_UPDATED` event on **every render**.
    2.  The machine has a global event handler for `CONTEXT_UPDATED`. This handler has a crucial **guard**: `guard: ({ context }) => !context.sideEffect`.
    3.  This means the machine will **only re-evaluate its state (`target: '.evaluating'`) if it has not already commanded a side-effect**.
    4.  If a side-effect *is* active (e.g., `action: 'navigateAndSaveJournal'`), the machine will stay in its current state (e.g., `redirectingFromLogin`) and simply update its context. It will not re-run the `entry` action or re-evaluate its `always` transitions.
    5.  It then relies on local `on.CONTEXT_UPDATED` handlers within states like `redirectingFromLogin` to watch for the *result* of the side-effect (e.g., the `pathname` changing). Once the change is observed, it transitions to the next state (`cleanupAfterRedirect`).

This "side-effect lock" mechanism is the core defense against the race conditions that cause redirect loops with Fast Refresh.

---

## 4. The `loginUiMachine`

-   **File**: `app/src/atoms/login-ui-machine.ts`
-   **Purpose**: A simple, presentational machine to control the UI of the `/login` page.

### Key States

-   `idle`: Waiting for an `EVALUATE` event.
-   `evaluating`: Transient state to decide what to show.
-   `showingForm`: The user is unauthenticated on the login page; show the login form.
-   `finalizing`: The user is authenticated (or logging in) but still on the login page. Shows a "Finalizing login..." spinner while the `navigationMachine` handles the redirect.

---

## 5. The `NavigationManager` Component

-   **File**: `app/src/atoms/NavigationManager.tsx`
-   **Purpose**: To act as the imperative "glue" between the declarative state machines and the React/Next.js environment.

### Responsibilities

1.  **Gathers Context**: It subscribes to all Jotai atoms relevant to navigation (`pathname`, `isAuthenticated`, `isAuthStable`, `setupPath`, etc.).
2.  **Dispatches Events**: On every render, it packages this context into a single object and sends it to the `navigationMachine` via a `CONTEXT_UPDATED` event.
3.  **Executes Side-Effects**: It subscribes to the `navigationMachine`'s state. It watches the `state.context.sideEffect` property. If it sees a command (e.g., `{ action: 'navigateAndSaveJournal', targetPath: '/' }`), it executes the corresponding imperative code (e.g., `router.push('/')`).

---

## 6. Detailed Flow Example: Initial Load with Expired Token

This flow demonstrates how all the pieces work together to handle a common, complex scenario.

1.  **Initial State**: App loads. `authMachine` is `uninitialized`. `navigationMachine` is `booting`.
2.  **Client Ready**: `JotaiAppProvider` initializes the REST client. `authMachine` receives `CLIENT_READY` and transitions to `checking`.
3.  **Auth Check**: `authMachine` invokes the `checkAuthStatus` actor. The API returns `expired_access_token_call_refresh: true`.
4.  **Refresh Needed**: `authMachine` transitions to `evaluating_initial_session`, sees the refresh flag, and immediately transitions to `initial_refreshing`.
    -   During this time, `authMachine` has the `ui-authenticated` tag, so the main layout does not unmount.
5.  **Token Refresh**: `authMachine` invokes the `refreshToken` actor. The API call succeeds and returns a new valid session.
6.  **Auth Stable**: `authMachine` transitions to `idle_authenticated.stable`. It now has the `auth-stable` tag. The `isAuthStable` atom becomes `true`.
7.  **Navigation Evaluates**: The user is currently on `/login`. The `NavigationManager` sends a `CONTEXT_UPDATED` event to the `navigationMachine` with `{ isAuthenticated: true, isAuthStable: true, pathname: '/login' }`.
8.  **Redirect Commanded**: The `navigationMachine` transitions `evaluating` -> `redirectingFromLogin`. Its `entry` action sets its `sideEffect` to `{ action: 'navigateAndSaveJournal', targetPath: '/' }`.
9.  **Side-Effect Lock**: Fast Refresh may trigger another render. `NavigationManager` sends another `CONTEXT_UPDATED` event. The `navigationMachine` sees that `context.sideEffect` is set, so its global event handler **does not** transition to `evaluating`. It stays in `redirectingFromLogin` and just updates its context. The loop is prevented.
10. **Redirect Executed**: The `NavigationManager`'s effect hook sees the `sideEffect` and calls `router.push('/')`.
11. **URL Changes**: The browser navigates. `usePathname()` now returns `/`.
12. **Confirmation**: `NavigationManager` renders again and sends `CONTEXT_UPDATED` with `{ pathname: '/' }`.
13. **Cleanup**: The `redirectingFromLogin` state's local `on.CONTEXT_UPDATED` handler now sees that `event.value.pathname` is not `/login`. Its guard passes, and it transitions to `cleanupAfterRedirect`.
14. **Final State**: `cleanupAfterRedirect` does its work and transitions to `evaluating`, which then transitions to the final, stable `idle` state. The flow is complete.

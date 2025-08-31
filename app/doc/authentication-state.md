# STATBUS Authentication and State Management

This document provides a detailed overview of the authentication state management, navigation, and redirect logic within the STATBUS application, powered by Jotai. Understanding these flows is crucial for debugging and extending the application.

## Core Principles

1.  **Single Source of Truth**: All authentication state is managed within Jotai atoms. There are no separate contexts or stores.
2.  **Centralized API Calls**: API calls for auth status, login, and logout are encapsulated within dedicated "action" atoms.
3.  **Stabilized Auth State ("Non-Flapping")**: The UI and data-fetching logic are shielded from transient authentication state changes (e.g., `true -> false -> true`) that can occur during background token refreshes. This prevents UI flicker and unnecessary data refetching.
4.  **Centralized Programmatic Navigation**: All programmatic redirects (i.e., navigation not initiated by a user clicking a `<Link>`) are handled by a single `RedirectHandler` component, driven by state in Jotai atoms. Direct calls to `router.push()` are forbidden outside of this handler.

## Key Atoms and Their Purpose

The authentication state flows through a chain of atoms, starting from a core API promise and ending with stabilized, UI-ready data.

### 1. Core Data and API Interaction

-   `restClientAtom` (`app.ts`)
    -   **Purpose**: Holds the initialized PostgREST client instance. It starts as `null`.
    -   **Flow**: It's populated by a `useEffect` in `AppInitializer` once the client is ready. Its presence is a prerequisite for most data-fetching atoms.

-   `authStatusPromiseAtom` (`auth.ts`)
    -   **Purpose**: The foundational atom. It holds the `Promise` returned by an authentication API call (`auth_status`, `login`, `refresh`, etc.). It does *not* hold the data itself.
    -   **Flow**: It is written to by action atoms like `fetchAuthStatusAtom`, `loginAtom`, and `clientSideRefreshAtom`. Other atoms read its status via `authStatusLoadableAtom`.

-   `fetchAuthStatusAtom` (`auth.ts`)
    -   **Purpose**: A write-only "action" atom. Its sole job is to call the `/rpc/auth_status` endpoint and update `authStatusCoreAtom` with the resulting promise.
    -   **Flow**: Triggered by `AppInitializer` once `restClientAtom` is ready.

-   `authStatusLoadableAtom` (`auth.ts`)
    -   **Purpose**: A utility atom from `jotai/utils` that wraps `authStatusCoreAtom`.
    -   **Flow**: It provides a synchronous view of the promise's state (`{ state: 'loading' | 'hasData' | 'hasError', data?: ... }`). This is critical for avoiding component suspension and for building the stabilized state.

### 2. State Interpretation and Stabilization

-   `authStatusUnstableDetailsAtom` (`auth.ts`)
    -   **Purpose**: **This is a key atom for stabilization.** It reads `authStatusLoadableAtom` and translates it into a consistent `ClientAuthStatus` object (`{ loading, isAuthenticated, user, ... }`).
    -   **Key Behavior**: When `authStatusLoadableAtom` is in the `loading` state, this atom checks if there is stale data from a previous successful fetch. If so, it returns `{ loading: true, ...staleData }`. This is the core of the "non-flapping" mechanism.

-   `isUserConsideredAuthenticatedForUIAtom` (`auth.ts`)
    -   **Purpose**: A **stabilized** boolean for UI components and navigation logic.
    -   **Flow**: Returns `true` if the user is authenticated OR if a token refresh is in progress. This prevents UI flicker (e.g., momentarily showing a login page) during background refreshes. This should be used for any logic that controls what the user *sees*.

-   `isAuthenticatedStrictAtom` (`auth.ts`)
    -   **Purpose**: A **strict** boolean, primarily for gating logic in `useEffect` hooks that should only run once a session is confirmed.
    -   **Flow**: Returns `true` only when the application has a valid session (`'authenticated'` or initial `'refreshing'`). It is `false` during the initial `'checking'` phase, making it stricter than its UI counterpart. For atoms that fetch data and can suspend, `authStateForDataFetchingAtom` should be used directly.

-   `authStatusAtom` (`auth.ts`)
    -   **Purpose**: The main, UI-facing atom for components. It provides the full auth state details (`user`, `loading`, etc.).
    -   **Flow**: It is composed using the UI-stable `isUserConsideredAuthenticatedForUIAtom`, so that components using the `useAuth()` hook get the non-flapping behavior by default.
    -   **Flow**: This should be the default atom used by UI components via the `useAuth()` hook.

### 3. Navigation and Redirect State

-   `initialAuthCheckCompletedAtom` (`app.ts`)
    -   **Purpose**: A simple boolean flag that is set to `true` once the very first authentication check completes successfully.
    -   **Flow**: A `useEffect` in `AppInitializer` sets this. Its purpose is to prevent `RedirectGuard` from making a redirect decision before the app has had a chance to determine the initial auth state.

-   `lastKnownPathBeforeAuthChangeAtom` (`auth.ts`)
    -   **Purpose**: Stores the user's last valid URL before being redirected to `/login`. It uses `sessionStorage` to survive page reloads within a single tab.
    -   **Flow**: The `PathSaver` component continuously updates this atom with the current URL as long as the user is authenticated.

-   `requiredSetupRedirectAtom` (`app.ts`)
    -   **Purpose**: Signals a mandatory redirect to a setup page based on the application's state (e.g., missing configuration).
    -   **Flow**: A `useEffect` in `AppInitializer` reads the result of `setupRedirectCheckAtom` when the user is on the dashboard (`/`). If a setup path is required, it sets this atom, which is then consumed by the `RedirectHandler`.

-   `setupRedirectCheckAtom` (`app.ts`)
    -   **Purpose**: The single source of truth for determining if a setup redirect is required. It encapsulates all the necessary data dependencies (`baseData`, `numberOfRegions`, etc.).
    -   **Flow**: It returns an object `{ path: string | null, isLoading: boolean }`. This allows consumers like `LoginClientBoundary` to wait for the check to complete before making a redirect decision, preventing race conditions and visual flashes.

## Major Authentication Flows

### 1. Initial Application Load

1.  `JotaiAppProvider` mounts `AppInitializer`.
2.  `useEffect` in `AppInitializer` asynchronously initializes the REST client and sets `restClientAtom`.
3.  A subsequent `useEffect` sees `restClientAtom` has a value and calls the `fetchAuthStatusAtom` action.
4.  `fetchAuthStatusAtom` calls the `/rpc/auth_status` endpoint and places the returned `Promise` into `authStatusPromiseAtom`.
5.  `authStatusLoadableAtom` transitions to `{ state: 'loading' }`.
6.  `authStatusUnstableDetailsAtom` sees this and returns `{ loading: true, isAuthenticated: false, ... }`. Both `isAuthenticatedStrictAtom` (strict) and `isUserConsideredAuthenticatedForUIAtom` (UI) return `false`.
7.  The API promise resolves. `authStatusLoadableAtom` transitions to `{ state: 'hasData', data: ... }`.
8.  `authStatusUnstableDetailsAtom` now returns `{ loading: false, ...data }`. Both auth atoms now return the correct authenticated status (e.g., `true`).
9.  A `useEffect` in `AppInitializer` sees that `authStatusLoadableAtom` is now `'hasData'` and sets `initialAuthCheckCompletedAtom` to `true`.
10. The `RedirectGuard` can now safely evaluate the user's authentication state and decide if a redirect is needed.

### 2. Background Token Refresh (The "Non-Flap")

1.  The application detects an expired access token (e.g., from an API response or from the `expired_access_token_call_refresh` flag).
2.  A `useEffect` in `AppInitializer` calls the `clientSideRefreshAtom` action.
3.  `clientSideRefreshAtom` makes a `fetch` call to `/rpc/refresh` and places the new `Promise` into `authStatusPromiseAtom`.
4.  `authStatusLoadableAtom` transitions to `{ state: 'loading', data: <stale_auth_data> }`. **Crucially, Jotai preserves the data from the last successful resolution.**
5.  `authStatusUnstableDetailsAtom` reads this state. It detects `'loading'` but also sees the stale data and returns `{ loading: true, ...stale_auth_data }`.
6.  `isUserConsideredAuthenticatedForUIAtom` reads the stale data and continues to return `true`. UI components and navigation guards remain stable.
7.  `isAuthenticatedAtom` (the strict one) sees that a refresh is pending (via `expired_access_token_call_refresh: true` in the stale data) and returns `false`.
8.  **Result**: Data-fetching atoms that depend on the strict `isAuthenticatedAtom` (like `baseDataPromiseAtom`) are now paused. UI components that depend on `isUserConsideredAuthenticatedForUIAtom` see no change and do not flicker. The race condition is resolved.
8.  The refresh promise resolves. The state propagates as in the initial load, and the application now has a new valid access token.

### 3. User Login

1.  User submits the login form, which calls the `loginAtom` action.
2.  `loginAtom` sends a `LOGIN` event to the central `authMachine`, which transitions into its `loggingIn` state while it performs the authentication.
3.  The `LoginClientBoundary` component on the `/login` page, now driven by its own local UI state machine, reacts to the global `authMachine`'s `loggingIn` state and transitions to a `finalizing` state, displaying a "Finalizing login..." message.
4.  Simultaneously, the central `NavigationManager` receives the updated context from `authMachine` (`isAuthenticated: true`, `pathname: '/login'`).
5.  The `navigationMachine` sees an authenticated user on the login page and transitions to the `redirectingFromLogin` state.
6.  This state's `entry` action calculates the correct redirect path, prioritizing: (1) a required setup path, (2) the `lastKnownPathBeforeAuthChange`, or (3) the dashboard (`/`). It then sets a `sideEffect` in its context to navigate to this path.
7.  The `NavigationManager` observes this side-effect and executes `router.push()`.
8.  After navigating away from `/login`, the `navigationMachine` recognizes that the login flow is complete (by observing the `authMachine`'s state and the change in pathname) and can perform any necessary cleanup, such as clearing `lastKnownPathBeforeAuthChangeAtom`.

#### The Login Page State Machine (`loginPageMachine`)

The UI logic on the login page is managed by a small XState state machine (`loginPageMachine` defined in `auth.ts`) to prevent race conditions and ensure a predictable user experience. This is especially important because the component re-evaluates its state based on multiple asynchronous inputs (user authentication status and the current browser path).

The machine has the following states:

-   `idle`: The initial state. It waits for an `EVALUATE` event to begin processing.
-   `evaluating`: The central decision-making state. It uses guards to immediately transition to either `finalizing` or `showingForm` based on the current context (`isAuthenticated` and `isOnLoginPage`).
-   `showingForm`: The machine is in this state when it's appropriate to display the login form to the user (i.e., they are unauthenticated on the login page).
-   `finalizing`: The machine enters this state when the user is successfully authenticated but is still on the login page. The UI shows a "Finalizing login..." message while it waits for the redirect to happen. This state has `always` transitions that automatically move it to `showingForm` if auth is lost, or to `idle` once the user is no longer on the login page (i.e., the redirect has completed).

This state machine approach makes the login UI robust against re-renders from React's Strict Mode or Fast Refresh, which could otherwise cause loops or inconsistent behavior.

### 4. User Logout

1.  User clicks logout, which calls the `logoutAtom` action.
2.  `logoutAtom` calls the `/rpc/logout` endpoint. If this call fails, an error is thrown for the UI to handle, and the logout process is aborted.
3.  Upon success, it directly updates `authStatusPromiseAtom` with the new unauthenticated status. This change propagates through the atom graph, causing dependent atoms like `baseDataAtom` to automatically reset to their initial state.
4.  It then proceeds to explicitly reset all other relevant application state atoms that do not react to auth changes (e.g., `searchStateAtom`).
5.  The state change to unauthenticated is detected by the `NavigationManager`, which transitions the `navigationMachine` to `savingPathForLoginRedirect` and then `redirectingToLogin`, handling the navigation automatically.

### 5. Conditional Setup Redirects (from Dashboard)

This flow handles cases where an already-authenticated user lands on the dashboard but still needs to complete a setup step.

1.  The user navigates to the dashboard (`/`).
2.  A `useEffect` in `AppInitializer` runs. It sees the user is on the dashboard and is authenticated.
3.  It reads the result from the central `setupRedirectCheckAtom`. This atom has already determined if a setup redirect is needed and what the path should be.
4.  The `useEffect` sets `requiredSetupRedirectAtom` to the path provided by `setupRedirectCheckAtom` (or `null` if no redirect is needed).
5.  The `RedirectHandler` sees that `requiredSetupRedirectAtom` has a value and redirects the user to the appropriate setup page.

## Redirect and Navigation Logic (State Machine)

Programmatic navigation (redirects not initiated by a user clicking a `<Link>`) is handled by a robust, centralized XState state machine to prevent race conditions and tangled `useEffect` dependencies. This replaces the previous system of multiple, interacting `RedirectGuard` and `RedirectHandler` components.

The system consists of two main parts:

-   `navigationMachineAtom` (`navigation-machine.ts`)
    -   **Job**: An XState state machine that serves as the single source of truth for all navigation decisions. It receives context (authentication status, current path, setup requirements) and transitions between explicit states (`booting`, `evaluating`, `redirectingToLogin`, `idle`, etc.).
    -   **Logic**: The machine's transitions are governed by guards that check the application's state. Based on its current state, it produces a `sideEffect` object in its context, instructing the `NavigationManager` on what action to perform (e.g., `navigate`, `savePath`).

-   `NavigationManager` (`NavigationManager.tsx`)
    -   **Job**: A simple component mounted in `JotaiAppProvider` that acts as the bridge between Jotai and the state machine.
    -   **Logic**: On every render, it:
        1.  Gathers all relevant state from various Jotai atoms.
        2.  Sends this state to the `navigationMachineAtom` as a `CONTEXT_UPDATED` event.
        3.  Observes the `sideEffect` object in the machine's state.
        4.  Executes the commanded side-effect, such as calling `router.push()` or updating other Jotai atoms.

This architecture ensures that navigation is a predictable, testable, and deterministic function of the application's state, eliminating an entire class of bugs related to timing and asynchronous operations.

### Conditional Setup Redirects (from Dashboard)

This flow handles cases where an already-authenticated user lands on the dashboard but still needs to complete a setup step.

1.  The user navigates to the dashboard (`/`).
2.  The `NavigationManager` sends the updated `pathname` to the `navigationMachine`.
3.  The machine transitions to its `evaluating` state.
4.  A guard checks for three conditions: the user is authenticated, the current `pathname` is `/`, and the `setupRedirectCheckAtom` has determined a required setup path (e.g., `/getting-started/activity-standard` or `/import`).
5.  If all conditions are met, the machine transitions to the `redirectingToSetup` state.
6.  This state's `entry` action sets a `sideEffect` in the context to navigate to the required setup path.
7.  The `NavigationManager` sees this side-effect and calls `router.push()`, redirecting the user.

Because the guard explicitly checks for `pathname === '/'`, this redirect logic is only triggered from the dashboard, allowing the user to freely navigate to other pages like `/profile` even if setup is incomplete.

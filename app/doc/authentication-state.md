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

-   `isAuthenticatedAtom` (`auth.ts`)
    -   **Purpose**: The primary, **stabilized** boolean value for the user's authentication status.
    -   **Flow**: It derives its state from `authStatusUnstableDetailsAtom`. Because `authStatusUnstableDetailsAtom` provides stale data during re-validation, this atom will consistently return `true` during a token refresh, preventing downstream consumers from seeing a momentary `false` state. **All data-fetching atoms should depend on this atom.**

-   `authStatusAtom` (`auth.ts`)
    -   **Purpose**: The main, UI-facing atom. It provides the full auth state details (`user`, `loading`, etc.) but overwrites the raw `isAuthenticated` flag with the stabilized one from `isAuthenticatedAtom`.
    -   **Flow**: This should be the default atom used by UI components via the `useAuth()` hook.

### 3. Navigation and Redirect State

-   `initialAuthCheckCompletedAtom` (`app.ts`)
    -   **Purpose**: A simple boolean flag that is set to `true` once the very first authentication check completes successfully.
    -   **Flow**: A `useEffect` in `AppInitializer` sets this. Its purpose is to prevent `RedirectGuard` from making a redirect decision before the app has had a chance to determine the initial auth state.

-   `lastKnownPathBeforeAuthChangeAtom` (`auth.ts`)
    -   **Purpose**: Stores the user's last valid URL before being redirected to `/login`. It uses `sessionStorage` to survive page reloads within a single tab.
    -   **Flow**: The `PathSaver` component continuously updates this atom with the current URL as long as the user is authenticated.

-   `pendingRedirectAtom` (`app.ts`)
    -   **Purpose**: The central signal for triggering a programmatic redirect.
    -   **Flow**: Set by components/atoms like `RedirectGuard` (to `/login`), `loginAtom` (to `/`), or `logoutAtom` (to `/login`). The `RedirectHandler` component listens to this atom and executes the navigation.

-   `isLoginActionInProgressAtom` (`auth.ts`)
    -   **Purpose**: A flag to signal that a fresh login action is in progress.
    -   **Flow**: `loginAtom` sets this to `true`. This allows `RedirectHandler` to perform specific cleanup actions (like clearing `lastKnownPathBeforeAuthChangeAtom`) only after a redirect triggered by a login, ensuring state from a previous session is properly cleared.

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
6.  `authStatusUnstableDetailsAtom` sees this and returns `{ loading: true, isAuthenticated: false, ... }`. `isAuthenticatedAtom` returns `false`.
7.  The API promise resolves. `authStatusLoadableAtom` transitions to `{ state: 'hasData', data: ... }`.
8.  `authStatusUnstableDetailsAtom` now returns `{ loading: false, ...data }`. `isAuthenticatedAtom` returns the correct authenticated status (e.g., `true`).
9.  A `useEffect` in `AppInitializer` sees that `authStatusLoadableAtom` is now `'hasData'` and sets `initialAuthCheckCompletedAtom` to `true`.
10. The `RedirectGuard` can now safely evaluate the user's authentication state and decide if a redirect is needed.

### 2. Background Token Refresh (The "Non-Flap")

1.  The application detects an expired access token (e.g., from an API response or from the `expired_access_token_call_refresh` flag).
2.  A `useEffect` in `AppInitializer` calls the `clientSideRefreshAtom` action.
3.  `clientSideRefreshAtom` makes a `fetch` call to `/rpc/refresh` and places the new `Promise` into `authStatusPromiseAtom`.
4.  `authStatusLoadableAtom` transitions to `{ state: 'loading', data: <stale_auth_data> }`. **Crucially, Jotai preserves the data from the last successful resolution.**
5.  `authStatusUnstableDetailsAtom` reads this state. It detects `'loading'` but also sees the stale data and returns `{ loading: true, ...stale_auth_data }`.
6.  `isAuthenticatedAtom` reads from `authStatusUnstableDetailsAtom`. Since the stale data has `isAuthenticated: true`, it continues to return `true`.
7.  **Result**: Downstream atoms like `baseDataPromiseAtom` and UI components that depend on `isAuthenticatedAtom` see no change and do not re-run or flicker. The application state remains stable.
8.  The refresh promise resolves. The state propagates as in the initial load, and the application now has a new valid access token.

### 3. User Login

1.  User submits the login form, which calls the `loginAtom` action.
2.  `loginAtom` sets `isLoginActionInProgressAtom` to `true` and updates `authStatusPromiseAtom` with the new, authenticated status.
3.  The `LoginClientBoundary` component, active on the `/login` page, reacts to the auth state change. Its internal state machine transitions to a `finalizing` state, and the UI displays a "Finalizing login..." message.
4.  A `useEffect` within `LoginClientBoundary` now waits for the `setupRedirectCheckAtom` to finish loading.
5.  Once the check is complete, the `useEffect` determines the single, correct destination path. The priority is: (1) a required setup path, (2) a pre-auth path from another tab, (3) the `next` URL parameter, or (4) the dashboard (`/`).
6.  It then sets `pendingRedirectAtom` with this final path. This single action prevents any intermediate redirects or visual flashes of the dashboard.
7.  The `RedirectHandler` component executes the redirect.
8.  Upon arrival at the destination, the `RedirectHandler` performs its standard cleanup, clearing `pendingRedirectAtom` and, because `isLoginActionInProgressAtom` is true, also clearing the post-login state.

### 4. User Logout

1.  User clicks logout, which calls the `logoutAtom` action.
2.  `logoutAtom` calls the `/rpc/logout` endpoint. If this call fails, an error is thrown for the UI to handle, and the logout process is aborted.
3.  Upon success, it directly updates `authStatusPromiseAtom` with the new unauthenticated status. This change propagates through the atom graph, causing dependent atoms like `baseDataAtom` to automatically reset to their initial state.
4.  It then proceeds to explicitly reset all other relevant application state atoms that do not react to auth changes (e.g., `searchStateAtom`).
5.  Finally, it sets `pendingRedirectAtom` to `'/login'`.
6.  The `RedirectHandler` sees this change and navigates the user to the login page.

### 5. Conditional Setup Redirects (from Dashboard)

This flow handles cases where an already-authenticated user lands on the dashboard but still needs to complete a setup step.

1.  The user navigates to the dashboard (`/`).
2.  A `useEffect` in `AppInitializer` runs. It sees the user is on the dashboard and is authenticated.
3.  It reads the result from the central `setupRedirectCheckAtom`. This atom has already determined if a setup redirect is needed and what the path should be.
4.  The `useEffect` sets `requiredSetupRedirectAtom` to the path provided by `setupRedirectCheckAtom` (or `null` if no redirect is needed).
5.  The `RedirectHandler` sees that `requiredSetupRedirectAtom` has a value and redirects the user to the appropriate setup page.

## Redirect and Navigation Component Logic

The redirect system is orchestrated by three components mounted inside `JotaiAppProvider`.

-   `PathSaver`
    -   **Job**: Continuously saves the current path to `lastKnownPathBeforeAuthChangeAtom` via a `useEffect` whenever `isAuthenticated` is `true`. This ensures the last known good location is always available in `sessionStorage`.

-   `RedirectGuard`
    -   **Job**: Protects private routes from unauthenticated access.
    -   **Logic**: A `useEffect` runs when `pathname`, `isAuthenticated`, or `authLoadable` change.
    -   It **waits** for `initialAuthCheckCompletedAtom` to be `true`.
    -   If the user is **not** authenticated, auth is **not** loading, and they are not on a public path, it sets `pendingRedirectAtom` to `'/login'`.

-   `RedirectHandler`
    -   **Job**: The **only** component that executes `router.push()` for programmatic redirects. It handles two types of redirects with different rules:
        -   **Explicit Redirects** (from `pendingRedirectAtom`): Used for login/logout. These target an *exact* path.
        -   **Setup Redirects** (from `requiredSetupRedirectAtom`): Used for guiding users. These target a *path prefix* (e.g., `/import`), allowing navigation to sub-pages like `/import/jobs`.
    -   **Logic**: A `useEffect` runs on every navigation. Explicit redirects are always handled first.
        1.  **Handle Explicit Redirect**:
            -   **Execute**: If `pendingRedirectAtom` is set and the user is not at the exact target path, it calls `router.push()`.
            -   **Cleanup**: Upon arrival at the exact path, it clears `pendingRedirectAtom` to prevent loops. It also performs post-login cleanup if needed.
            -   **Cancel**: If the user navigates elsewhere manually, the pending redirect is cancelled.
        2.  **Handle Setup Redirect**:
            -   **Execute**: If no explicit redirect is active, `requiredSetupRedirectAtom` is set, and the user's current path does not *start with* the target path, it calls `router.push()`. This enforces that the user stays within the required setup section.
            -   **No Cleanup on Arrival**: The `requiredSetupRedirectAtom` is *not* cleared upon arrival. This makes the redirect "sticky". It will only be cleared when the underlying setup condition is resolved (logic in `AppInitializer`) or if the user manually navigates to an unrelated part of the application.
            -   **Cancel**: If the user navigates to a path outside the required section, the pending redirect is cancelled.

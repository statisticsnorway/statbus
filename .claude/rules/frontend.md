---
paths:
  - "app/**"
---

# Next.js Application Conventions (STATBUS)

Core conventions for the Next.js (v15) application. For SQL and infrastructure conventions, see `.claude/rules/sql.md`.

## General
- Language: TypeScript.
- Routing: Next.js App Router (`app/` directory). Use `route.ts` for pages and API routes.
- HTTP: Named exports for methods. Use `NextResponse` for responses.
- API Organization: Group under `app/api/` matching endpoint structure.
- Exports: Prefer named exports over default exports.
- Styling: Tailwind CSS.
- UI Components: shadcn/ui. Group custom components by feature in `components/`.
- Testing: Jest and ts-jest.
- Build/Deployment: Standard Next.js scripts in `package.json`.
- Type Checking: To run the TypeScript compiler and check for type errors without emitting files, use the following command from the project root: `cd app && pnpm run tsc`.
- Principles:
    - Fail Fast: For functionality expected to work. Provide clear error/debug info.
    - Single Source of Truth: Avoid duplicate state.
    - Complete Refactoring: When refactoring, fully migrate without lingering compatibility layers.
    - Readability: Prioritize clear code over excessive comments for explaining logic. Internal thought-process comments should be removed.
    - Think from first principles.
    - Clean Code and Commenting:
        - Strive for self-documenting code. Well-named variables, functions, and classes can often make the code's purpose clear without needing comments.
        - Git for Change Tracking: Git is our tool for tracking the history of *what* changes were made, *who* made them, and *when*. Commit messages should be descriptive and explain the "what" and "why" of a change set.
        - Purpose of Comments: Comments in the code should primarily explain *why* a particular piece of code exists or *why* a certain approach was taken, especially if it's non-obvious. They can also be used to organize code (e.g., section headers) or to leave TODOs/FIXMEs.
        - Avoid Redundant Comments: Do not add comments that merely restate what the code is doing (e.g., `// increment i` for `i++`). Similarly, comments detailing trivial changes like "removed line X" or "added import Y" are redundant as Git tracks these. Such comments add noise and reduce readability.

## State Management (Jotai)
- **Primary Library**: Jotai is used for client-side global state management. For more details on Jotai utilities and extensions relevant to this project, see `doc/jotai.md`.
- **Structure**: Atoms and their related hooks are co-located in feature-specific files within the `app/src/atoms/` directory (e.g., `app/src/atoms/auth.ts`, `app/src/atoms/search.ts`).
- **Imports**: Components must import atoms and hooks directly from their feature-specific source file. A barrel file is not used.
- **Initialization**: Global state is initialized within the `<JotaiAppProvider>` component (`app/src/atoms/JotaiAppProvider.tsx`). This provider contains initializer components and hooks (like `useAppInitialization`) that manage application startup logic.
- **Patterns**:
    - **Atomic State**: Prefer small, independent atoms. **This is the most critical convention for preventing re-render loops.**
        - **Avoid Monolithic State Objects**: Do not consolidate multiple, independently-updated pieces of state into a single large object within one atom. Doing so creates unstable object references, where an update to one piece of state forces components that subscribe to *other, unchanged* pieces of state to re-render. This was the root cause of the `/search` page infinite loop.
        - **Principle of Isolation**: If a piece of state can change on its own, it **MUST** live in its own atom.
        - **Reference Implementation**: The refactoring of the original `searchStateAtom` into four independent atoms (`queryAtom`, `filtersAtom`, `sortingAtom`, `paginationAtom`) is the canonical example of this pattern.
    - **Derived Atoms**: Compute state from other atoms for efficient re-renders.
    - **Action Atoms**: Use write-only or read/write atoms to encapsulate state update logic and side effects (e.g., API calls that modify global state).
- **Data Fetching for Global State**:
    - For server state that needs to become part of global client state (e.g., user profile, application base data), use Jotai's async atoms or action atoms that fetch data and update state atoms. This ensures the data is integrated into the Jotai ecosystem.
    - **Managing Asynchronous State and Side Effects (e.g., Navigation):**
        - When an action atom (e.g., `loginAtom`, `logoutAtom`) modifies an underlying asynchronous core atom (e.g., `authStatusCoreAtom`), ensure the action atom awaits the completion of the core atom's refresh if subsequent logic or component reactions depend on the *stabilized* state. Example: `set(authStatusCoreAtom); await get(authStatusCoreAtom);`
        - Components performing side effects (like navigation via `router.push()`) based on Jotai state within `useEffect` hooks must ensure they react to a *stable* state. Check flags like `initialAuthCheckCompleted` and `authStatus.loading` to avoid acting on intermediate or stale data.
        - **Programmatic Navigation**: A distinction must be made between *application-level redirects* and *local state-to-URL synchronization*.
          - **Application-Level Redirects**: To prevent race conditions and ensure state consistency, all programmatic navigation that changes the user's location in the application flow (e.g., after login/logout, or for setup flows) **MUST** be handled by the centralized XState state machine (`navigation-machine.ts`). Components should not perform these types of redirects.
          - **Local State-to-URL Synchronization**: For features that reflect their state in the URL's query parameters on the *current page* (e.g., search filters), it is correct and expected to use the `useRouter` hook from `next/navigation`, specifically with `router.replace()`. The `useSearchUrlSync` hook is the reference implementation for this pattern.
          - **User-Initiated Navigation**: For direct, user-initiated navigation from within components (e.g., in a command palette or after a form submission), it is also correct to use the `useRouter` hook.
    - **Handling Complex Conditional Logic (e.g., Login Page):**
        - For UI flows with multiple conditions and potential race conditions (e.g., checking auth status, handling redirects, showing a form), use a state machine (`jotai-xstate`). This makes the logic explicit, robust, and immune to re-render loops caused by React Strict Mode or Fast Refresh.
        - The `LoginClientBoundary` is the reference implementation for this pattern. It uses a state machine to decide whether to show the login form or trigger a redirect away from the page.
    - **Managing State Across Page Reloads:**
        - For state that must be **per-tab** but also **survive a hard page reload** (which can be triggered by redirects in development), use `atomWithStorage` configured for `sessionStorage`.
        - The `lastKnownPathBeforeAuthChangeAtom` is the reference for this. It stores the user's last location so it can be restored after a logout/login cycle that involves a redirect.
    - **Decoupling State Updates from Side Effects:**
        - To avoid race conditions, decouple the act of saving state from the act of triggering a side effect.
        - The `PathSaver` component continuously saves the user's last authenticated location. The `RedirectGuard` component later reads this state when it needs to trigger a redirect, ensuring the value is stable and correct.

## API Architecture: Direct `/rest` vs Next.js `/api` Routes

**CRITICAL**: Prefer direct browser-to-`/rest` requests over proxying through Next.js `/api` routes.

### Why Direct `/rest` Requests Are Preferred

1. **Easier Debugging**: Direct `/rest` calls expose the actual request/response to and from the database, making it trivial to inspect what PostgREST is doing.
2. **User Integration**: Users can observe `/rest` calls in their browser's Network tab, learning the API patterns and enabling them to integrate their own systems using API keys.
3. **Transparency**: STATBUS offers API keys for external integrations. Direct `/rest` calls from the browser demonstrate the exact same API that external users will consume.
4. **Performance**: Eliminates an unnecessary proxy layer and reduces server-side compute.
5. **Security**: JWT tokens map directly to database roles with RLS policies. There are typically NO server-side secrets needed—authentication and authorization happen entirely at the database layer via PostgREST.

### When to Use Each Pattern

**Use Direct `/rest` Requests (Preferred)**:
- All standard CRUD operations (GET, POST, PATCH, DELETE)
- Filtered queries, pagination, sorting
- Calling database functions via PostgREST RPC
- Any operation where the database schema/RLS provides sufficient security

**Use Next.js `/api` Routes (Only When Required)**:
- **Performance optimizations** requiring direct database access (e.g., bulk uploads using PostgreSQL `COPY` command—see upload routes as reference)
- Operations requiring environment variables/secrets not exposed to browser (rare—JWT authentication eliminates most needs)
- Complex orchestration across multiple external services
- Webhook handlers from external systems
- Operations requiring server-side rate limiting beyond database capabilities

### Security: JWT Role Switching in `/api` Routes

**CRITICAL**: When using direct database connections in `/api` routes, `auth.jwt_switch_role()` **MUST** be called **BEFORE** `BEGIN`:

- Correct: `jwt_switch_role()` -> `BEGIN` -> operations -> `COMMIT`
- Vulnerable: `BEGIN` -> `jwt_switch_role()` -> operations (user could `ROLLBACK` to become `authenticator`)

Role changes inside a transaction are rolled back with `ROLLBACK`, allowing SQL injection to escalate privileges.

### Implementation Pattern

**Direct `/rest` Request (Preferred):**
```typescript
// In a component or Jotai atom
const response = await fetch('/rest/legal_units?id=eq.123', {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Accept': 'application/json',
  },
});
```

**Next.js `/api` Route (Only When Necessary):**
```typescript
// app/api/import/upload/route.ts - Performance optimization example
export async function POST(request: NextRequest) {
  // Extract JWT from cookies (same security model as /rest)
  const accessToken = request.cookies.get('statbus')?.value;
  if (!accessToken) {
    return NextResponse.json({ message: "Authentication required" }, { status: 401 });
  }

  // Connect as authenticator role, then switch to user's role via JWT
  const pool = new Pool({
    host: dbHost, port: dbPort, database: dbName,
    user: "authenticator",
    password: process.env.POSTGRES_AUTHENTICATOR_PASSWORD,
  });
  const pgClient = await pool.connect();

  // CRITICAL: Switch role BEFORE BEGIN to prevent ROLLBACK attack
  // If inside transaction, malicious SQL could ROLLBACK to become authenticator
  await pgClient.query('SELECT auth.jwt_switch_role($1)', [accessToken]);

  await pgClient.query('BEGIN');
  // Now perform efficient bulk operation with user's permissions
  await pgClient.query('COPY my_table FROM STDIN ...', streamData);
  await pgClient.query('COMMIT');

  return NextResponse.json({ imported: count });
}
```

## Data Fetching (SWR)
- `useSWR` is primarily used for fetching, caching, and revalidating component-level or UI-specific server state. This is suitable for data that doesn't need to be deeply integrated into the global Jotai state or shared across many distant parts of the application.
- Key SWR features like revalidation on focus/interval, local mutation, and request deduplication are beneficial for such use cases.
- **Data Source**: SWR should primarily fetch from `/rest` endpoints (see API Architecture above), not `/api` routes, unless there's a specific reason requiring server-side logic.
- **Interaction with Jotai**:
    - SWR's fetch keys can be derived from Jotai atoms (e.g., `useAtomValue(derivedParamsAtom)`). Changes in these Jotai atoms will naturally trigger SWR to re-fetch with the new key. This pattern is used in `SearchResults.tsx`.
    - SWR-fetched data can be synced back to global Jotai atoms using `useGuardedEffect` and `setAtom` if the data needs to be globally accessible or trigger other Jotai-dependent logic (as seen in `SearchResults.tsx` with `searchResultAtom`).
    - Jotai action atoms can also be used to trigger SWR revalidation explicitly (e.g., by calling `mutate` from `useSWRConfig`).
- **When to choose Jotai vs. SWR for server state**:
    - Use **Jotai** for server state that forms the foundation of your global application state (e.g., user authentication status, core application settings, base data used by many features).
    - Use **SWR** for data that is more localized to specific views/components, benefits from automatic revalidation strategies, or represents paginated/filtered lists where SWR's caching per key is advantageous.

## Debugging and Diagnostics

### `useGuardedEffect` for Loop Detection
To combat "Maximum update depth exceeded" errors and other lifecycle issues, the application is instrumented with a custom hook: `useGuardedEffect`.

- **Convention**: All React effects **MUST** use `useGuardedEffect` instead of the standard `useEffect`.
- **Architectural Purpose**: This hook provides a diagnostic system to detect two classes of infinite loops:
    1.  **Re-render loops:** When a single component instance re-renders rapidly, causing its effect to fire continuously.
    2.  **Re-mount loops:** When a component is destroyed and re-created in a loop, often caused by a parent component's state change. The original guard was blind to this, but the new version explicitly tracks component mounts.
- **Implementation**: `useGuardedEffect` is a drop-in replacement for `useEffect`. It accepts the same callback and dependency array, plus a third, mandatory argument: a unique string identifier.
- **Identifier Format**: The identifier **MUST** be a unique, descriptive string, typically in the format `'FileName.tsx:purposeOfEffect'`. This is crucial for providing clear, actionable information in the diagnostics panel.
- **Activation**: The diagnostic features are disabled by default (zero performance overhead). To activate them for a debugging session, add `NEXT_PUBLIC_ENABLE_EFFECT_GUARD=true` to your `.env.local` file and restart the server.
- **Diagnostic Panels**: When activated, two panels become available in the `StateInspector`:
    - **The Effect Journal**: Tracks effect call frequency to find re-render loops.
    - **The Component Mount Journal**: Tracks mount frequency to find re-mount loops.
- **Pattern for "Set-If-Null" Effects**:
    - For side effects that are intended to set a default value for a state atom only if it hasn't been set yet (e.g., setting a default time context on app load), the logic **MUST** be implemented in a Jotai `atomEffect`, not a `useGuardedEffect` inside a hook.
    - `atomEffect` decouples the side effect from the component render cycle, ensuring it runs only when its true dependencies (the source of the default value) change. Placing this logic in a hook that is consumed by frequently re-rendering components is an architectural flaw that leads to performance degradation.
    - **Reference Implementation**: The `timeContextAutoSelectEffectAtom` is the canonical example of this pattern. It is activated by being read once in a top-level component (`HomePage`).
- **Pattern for Subscribing to External Stores**:
    - When using `useEffect` or `useGuardedEffect` to subscribe to an external, non-React store (like the listener pattern in `use-toast.ts`), the dependency array **MUST** be empty (`[]`).
    - The effect should add the component's `setState` function to the listeners on mount and remove it on unmount (in the cleanup function). Including the component's `state` in the dependency array will create a feedback loop, causing the effect to re-run and re-subscribe on every state change, which is inefficient and a source of bugs.
    - **Reference Implementation**: The `listener` effect within the `useToast` hook is the canonical example of this pattern.
- **Pattern for Effects Reacting to State Machines**:
    - When writing an effect that performs side-effects based on a state machine's state (e.g., from `jotai-xstate`), the dependency array **MUST NOT** depend on the entire `state` object.
    - The `state` object from `jotai-xstate` is a new reference on every context update, even if the state *value* has not changed. Depending on the whole object will cause the effect to run on every render of the host component, leading to severe performance issues.
    - Instead, de-structure the specific, primitive values needed from the state object *before* the effect, and use those primitives in the dependency array. You **MUST** include `state.value` as a dependency to ensure the effect re-runs when the machine transitions to a new state.
    - **Reference Implementation**: The `performSideEffects` effect within the `NavigationManager` is the canonical example of this pattern. It depends on `stateValue`, `sideEffectAction`, and `sideEffectTargetPath` instead of the whole `state` object.
- **Decoupling Core Logic from Dev Tools**:
    - Core application logic (e.g., state machines, navigation managers) **MUST NOT** depend on the state of developer tools or diagnostic components (e.g., the `StateInspector`'s visibility).
    - Creating such a dependency causes the application's core logic to re-evaluate whenever a developer interacts with the UI of the tool, leading to severe performance degradation and masking other issues.
    - **Reference Implementation**: The `sendContextUpdates` effect in `NavigationManager` was refactored to remove its dependency on `isInspectorVisible`.

## Database Type Definitions
The file `app/src/lib/database.types.ts` contains TypeScript types automatically generated from the PostgreSQL schema (via `./devops/manage-statbus.sh generate-types`).
- **Table Rows**: `Tables<'my_table'>`
- **Enums**: `Enums<'my_enum'>`
- **Insert/Update**: `TablesInsert<'my_table'>`, `TablesUpdate<'my_table'>`
- **Regenerate**: After any schema change using the script.
Utilize these for type safety with database interactions.

## Next.js Specifics
- Use hooks from `next/navigation` (`usePathname`, `useSearchParams`) for client-side navigation.
- Global providers, including `<JotaiAppProvider>`, are placed in `app/src/app/layout.tsx`.

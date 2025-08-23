# Next.js Application Conventions (STATBUS)

Core conventions for the Next.js (v15) application. For project-wide, SQL, or infrastructure conventions, see `CONVENTIONS.md` in the project root.

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
- **Primary Library**: Jotai is used for client-side global state management. For more details on Jotai utilities and extensions relevant to this project, see [Jotai Utilities and Extensions for STATBUS](../doc/jotai.md).
- **Structure**: Atoms and their related hooks are co-located in feature-specific files within the `app/src/atoms/` directory (e.g., `app/src/atoms/auth.ts`, `app/src/atoms/search.ts`).
- **Imports**: Components must import atoms and hooks directly from their feature-specific source file. A barrel file is not used.
- **Initialization**: Global state is initialized within the `<JotaiAppProvider>` component (`app/src/atoms/JotaiAppProvider.tsx`). This provider contains initializer components and hooks (like `useAppInitialization`) that manage application startup logic.
- **Patterns**:
    - **Atomic State**: Prefer small, independent atoms.
    - **Derived Atoms**: Compute state from other atoms for efficient re-renders.
    - **Action Atoms**: Use write-only or read/write atoms to encapsulate state update logic and side effects (e.g., API calls that modify global state).
- **Data Fetching for Global State**:
    - For server state that needs to become part of global client state (e.g., user profile, application base data), use Jotai's async atoms or action atoms
that fetch data and update state atoms. This ensures the data is integrated into the Jotai ecosystem.
    - **Managing Asynchronous State and Side Effects (e.g., Navigation):**
        - When an action atom (e.g., `loginAtom`, `logoutAtom`) modifies an underlying asynchronous core atom (e.g., `authStatusCoreAtom`), ensure the action
atom awaits the completion of the core atom's refresh if subsequent logic or component reactions depend on the *stabilized* state. Example:
`set(authStatusCoreAtom); await get(authStatusCoreAtom);`
        - Components performing side effects (like navigation via `router.push()`) based on Jotai state within `useEffect` hooks must ensure they react to a
*stable* state. Check flags like `initialAuthCheckCompleted` and `authStatus.loading` to avoid acting on intermediate or stale data.
        - **Programmatic Navigation**: To prevent race conditions and ensure state consistency, all programmatic client-side navigation (i.e., redirects not initiated by a user clicking a standard `<Link>`) **MUST** be handled through a centralized, state-driven mechanism.
          - **DO NOT** call `router.push()`, `router.replace()`, or `window.location.href` directly from components, hooks, or action callbacks.
          - **INSTEAD**, set the `pendingRedirectAtom` with the target path.
          - A central `RedirectHandler` component within `JotaiAppProvider` observes this atom and executes the navigation. This approach guarantees that redirects are a controlled and predictable reaction to state changes.
    - **Handling Complex Conditional Logic (e.g., Login Page):**
        - For UI flows with multiple conditions and potential race conditions (e.g., checking auth status, handling redirects, showing a form), use a state machine (`jotai-xstate`). This makes the logic explicit, robust, and immune to re-render loops caused by React Strict Mode or Fast Refresh.
        - The `LoginClientBoundary` is the reference implementation for this pattern. It uses a state machine to decide whether to show the login form or trigger a redirect away from the page.
    - **Managing State Across Page Reloads:**
        - For state that must be **per-tab** but also **survive a hard page reload** (which can be triggered by redirects in development), use `atomWithStorage` configured for `sessionStorage`.
        - The `lastKnownPathBeforeAuthChangeAtom` is the reference for this. It stores the user's last location so it can be restored after a logout/login cycle that involves a redirect.
    - **Decoupling State Updates from Side Effects:**
        - To avoid race conditions, decouple the act of saving state from the act of triggering a side effect.
        - The `PathSaver` component continuously saves the user's last authenticated location. The `RedirectGuard` component later reads this state when it needs to trigger a redirect, ensuring the value is stable and correct.


## Data Fetching (SWR)
- `useSWR` is primarily used for fetching, caching, and revalidating component-level or UI-specific server state. This is suitable for data that doesn't need to be deeply integrated into the global Jotai state or shared across many distant parts of the application.
- Key SWR features like revalidation on focus/interval, local mutation, and request deduplication are beneficial for such use cases.
- **Interaction with Jotai**:
    - SWR's fetch keys can be derived from Jotai atoms (e.g., `useAtomValue(derivedParamsAtom)`). Changes in these Jotai atoms will naturally trigger SWR to re-fetch with the new key. This pattern is used in `SearchResults.tsx`.
    - SWR-fetched data can be synced back to global Jotai atoms using `useEffect` and `setAtom` if the data needs to be globally accessible or trigger other Jotai-dependent logic (as seen in `SearchResults.tsx` with `searchResultAtom`).
    - Jotai action atoms can also be used to trigger SWR revalidation explicitly (e.g., by calling `mutate` from `useSWRConfig`).
- **When to choose Jotai vs. SWR for server state**:
    - Use **Jotai** for server state that forms the foundation of your global application state (e.g., user authentication status, core application settings, base data used by many features).
    - Use **SWR** for data that is more localized to specific views/components, benefits from automatic revalidation strategies, or represents paginated/filtered lists where SWR's caching per key is advantageous.

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

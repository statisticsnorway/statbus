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

## State Management (Jotai)
- **Primary Library**: Jotai is used for client-side global state management.
- **Core Atoms**: Located in `app/src/atoms/index.ts`. Define base state units here.
    - Use `atomWithStorage` for persistent state (e.g., user preferences).
- **Utility Hooks**: Custom hooks for interacting with atoms and encapsulating common logic are in `app/src/atoms/hooks.ts`.
- **Provider**: A single `<JotaiAppProvider>` (from `app/src/atoms/JotaiAppProvider.tsx`) is used in the root layout (`app/src/app/layout.tsx`) to set up Jotai and initialize global state.
- **Patterns**:
    - **Atomic State**: Prefer small, independent atoms.
    - **Derived Atoms**: Compute state from other atoms for efficient re-renders.
    - **Action Atoms**: Use write-only or read/write atoms to encapsulate state update logic and side effects (e.g., API calls that modify global state).
- **Data Fetching for Global State**:
    - For server state that needs to become part of global client state (e.g., user profile, application base data), use Jotai's async atoms or action atoms that fetch data and update state atoms. This ensures the data is integrated into the Jotai ecosystem.

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
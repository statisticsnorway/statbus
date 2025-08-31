# TODO

- [x] ~~Improve StateInspector dev tools by adding a shared loading state for auth action buttons to prevent race conditions from rapid clicking.~~ (Resolved by fixing the underlying auth state flap, then fixed the parallel-refresh race condition with a global lock).
- [ ] Add toast notifications for auth errors (e.g., `REFRESH_FETCH_ERROR`) to give users feedback on transient connection issues.
- [x] ~~Fix redirect loop when navigating from a `/getting-started` page to `/profile`.~~ (Resolved by making the navigation machine's redirect-to-login guard stricter, requiring auth to be settled, not just loading).
- [x] ~~Remove obsolete `pendingRedirectAtom` and associated logic, fully committing to the navigation state machine.~~ (Resolved by removing the atom and updating documentation).
- [x] ~~Finalize removal of `pendingRedirectAtom` from all components and documentation.~~ (Resolved by replacing remaining usages with `useRouter`).
- [x] ~~Fix infinite loop/crash after login.~~ (Resolved by refactoring the state machine's post-login cleanup sequence to be event-driven instead of using unstable `always` transitions, which caused the infinite loop).
- [ ] Stabilize core state atoms (`workerStatusAtom`, `searchStateAtom`, etc.) using `selectAtom` to prevent unnecessary re-renders in consumers.
- [x] ~~Fix data cascade and navigation deadlocks caused by auth state propagation race condition.~~ (The nemesis bug was finally slain. Its true cause was a browser race condition. After a token refresh, client-side navigation would happen before the browser had processed the new `Set-Cookie` header, causing the navigation `fetch` to use the old, expired token and trigger a server redirect loop. The fix was to add a "canary" API call inside the `refreshToken` actor. By awaiting this canary call, we force the state machine to pause until the new cookie is confirmed to be working, thus synchronizing with the browser and preventing the loop.)
- [x] ~~Refactor authentication logic to use a declarative XState machine.~~ (Resolved by implementing `authMachine` and updating all dependent atoms and components, including fixing all TypeScript errors).

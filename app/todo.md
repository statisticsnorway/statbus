# TODO

- [x] ~~Implement and stabilize the declarative XState-based authentication and navigation state machines.~~ (The great war against the Nemesis is over. All known bugs related to state flaps, context flaps, race conditions, redirect loops, and infinite renders have been slain. The `authMachine` and `navigationMachine` are now the stable, single source of truth.)
- [x] ~~Verify all critical authentication and navigation scenarios, including server-forced redirects.~~ (Victory is confirmed. The system is stable.)
- [x] ~~Verify clean logout and redirect to login.~~ (Confirmed. Logout correctly clears state and redirects.)
- [x] ~~Slay the Event Journal hydration race condition.~~ (Victory is absolute. The realm's memory is now persistent and correct.)
- [ ] Add toast notifications for auth errors (e.g., `REFRESH_FETCH_ERROR`) to give users feedback on transient connection issues.
- [ ] Stabilize core state atoms (`workerStatusAtom`, etc.) using `selectAtom` to prevent unnecessary re-renders in consumers. This includes auditing them for unintended side-effects on reset.
- [x] ~~Refactor monolithic `useSearch` hook into granular, performant hooks using `selectAtom` to stabilize `searchStateAtom` consumers.~~

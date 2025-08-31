# TODO

- [x] ~~Implement and stabilize the declarative XState-based authentication and navigation state machines.~~ (The great war against the Nemesis is over. All known bugs related to state flaps, context flaps, race conditions, redirect loops, and infinite renders have been slain. The `authMachine` and `navigationMachine` are now the stable, single source of truth.)
- [ ] Add toast notifications for auth errors (e.g., `REFRESH_FETCH_ERROR`) to give users feedback on transient connection issues.
- [ ] Stabilize core state atoms (`workerStatusAtom`, `searchStateAtom`, etc.) using `selectAtom` to prevent unnecessary re-renders in consumers.

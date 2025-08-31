# TODO

- [x] ~~Implement and stabilize the declarative XState-based authentication and navigation state machines.~~ (The great war against the Nemesis is over. All known bugs related to state flaps, context flaps, race conditions, redirect loops, and infinite renders have been slain. The `authMachine` and `navigationMachine` are now the stable, single source of truth.)
- [x] ~~Verify all critical authentication and navigation scenarios, including server-forced redirects.~~ (Victory is confirmed. The system is stable.)
- [x] ~~Verify clean logout and redirect to login.~~ (Confirmed. Logout correctly clears state and redirects.)
- [x] ~~Slay the Event Journal hydration race condition.~~ (Victory is absolute. The realm's memory is now persistent and correct.)
- [x] ~~Fix React hydration error caused by `PageContentGuard`.~~ (The component was refactored into a client-only boundary wrapper to definitively prevent server-side suspension from causing a hydration mismatch.)
- [x] ~~Fix application getting stuck on "Loading application..." screen due to `PageContentGuard` deadlock.~~ (The guard's condition was updated to recognize `cleanupAfterRedirect` as a stable state.)
- [x] ~~Fix infinite re-render loop ("Maximum update depth exceeded") on page load.~~ (Removed the unstable `canaryScribeEffectAtom` which was causing a feedback loop between state changes and logging.)
- [x] ~~Fix second infinite re-render loop by disabling the unstable `navMachineScribeEffectAtom`.~~ (The scribe was a source of instability, but disabling it revealed a deeper root cause for the infinite loop.)
- [x] ~~Fix infinite re-render loop ("Maximum update depth exceeded").~~ (The unstable `setupRedirectCheckAtom` was stabilized using `selectAtom` to prevent it from returning new object references on every render, which was the root cause of the loop.)
- [x] ~~Create comprehensive, project-specific documentation for XState v5 and our established patterns.~~ (The Master Scribe has forged the scroll of knowledge at `app/doc/xstate_v5.md`.)
- [ ] Add toast notifications for auth errors (e.g., `REFRESH_FETCH_ERROR`) to give users feedback on transient connection issues.
- [ ] Stabilize core state atoms (`workerStatusAtom`, etc.) using `selectAtom` to prevent unnecessary re-renders in consumers. This includes auditing them for unintended side-effects on reset.
- [x] ~~Refactor state machine consumers (e.g., `PageContentGuard`) to use `state.hasTag()` instead of `state.matches()` where appropriate.~~ (The `navigationMachine` now uses a 'stable' tag, and the guard checks for it.)
- [x] ~~Fix the unstable `navMachineScribeEffectAtom`.~~ (The scribe's change-detection was made more robust by comparing both state value and context, fixing the infinite loop.)
- [ ] Create a generalized, development-only utility hook (`useAtomInstabilityDetector`) to diagnose unstable atoms that cause infinite re-render loops.
- [x] ~~Refactor monolithic `useSearch` hook into granular, performant hooks using `selectAtom` to stabilize `searchStateAtom` consumers.~~

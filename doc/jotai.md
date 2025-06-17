# Jotai Utilities and Extensions for STATBUS

This document outlines useful Jotai utilities and extensions relevant to the STATBUS project, which uses Next.js. For more detailed information on each, please refer to the official Jotai documentation.

## Core Concepts Recap

Jotai's core is minimal, built around the concept of atoms.
- **Atoms**: Represent a piece of state. They can be primitive (holding a value) or derived (computing a value from other atoms).
  ```typescript
  import { atom } from 'jotai';
  const countAtom = atom(0); // Primitive atom
  const doubledAtom = atom((get) => get(countAtom) * 2); // Derived atom
  ```
- **`useAtom`**: The primary hook to read an atom's value and get a function to update it.
  ```typescript
  const [count, setCount] = useAtom(countAtom);
  ```
- **`useAtomValue`**: Hook to read an atom's value (optimized for read-only scenarios).
- **`useSetAtom`**: Hook to get the update function for an atom (optimized for write-only scenarios).
- **Provider**: Essential for server-side rendering (SSR) and for creating custom Jotai stores. In Next.js (App Router), it's typically set up in a client component and used in the root layout.
  ```typescript
  // app/components/providers.tsx (or similar)
  'use client';
  import { Provider } from 'jotai';
  export const JotaiProvider = ({ children }) => <Provider>{children}</Provider>;

  // app/layout.tsx
  import { JotaiProvider } from '@/components/providers'; // Adjust path
  export default function RootLayout({ children }) {
    return (
      <html lang="en">
        <body>
          <JotaiProvider>{children}</JotaiProvider>
        </body>
      </html>
    );
  }
  ```
  STATBUS uses `<JotaiAppProvider>` in `app/src/app/layout.tsx`.

## Utilities (`jotai/utils`)

The `jotai/utils` module provides a collection of helpful functions and atom creators.

### `atomWithStorage`
- **Purpose**: Creates an atom that persists its state in Web Storage (`localStorage` or `sessionStorage`) and syncs across browser tabs (for `localStorage`).
- **Usage**:
  ```typescript
  import { atomWithStorage } from 'jotai/utils';
  const darkModeAtom = atomWithStorage('darkMode', false); // Persists in localStorage
  ```
- **Relevance**: Useful for user preferences, theme settings, etc. STATBUS uses this in `app/src/atoms/index.ts`.

### SSR and `useHydrateAtoms`
- **Purpose**: Jotai supports SSR. `useHydrateAtoms` is a utility to initialize atom values on the client with data fetched or computed on the server. The `Provider` is fundamental for SSR.
- **Relevance**: Critical for Next.js applications where initial state might come from server components or API calls during server rendering.

### `atomWithReset` / `useResetAtom`
- **Purpose**: `atomWithReset` creates an atom that can be reset to its initial value using the `useResetAtom` hook or by setting it to the `RESET` symbol.
- **Usage**:
  ```typescript
  import { atomWithReset, useResetAtom, RESET } from 'jotai/utils';
  const queryAtom = atomWithReset('');
  // In a component:
  // const resetQuery = useResetAtom(queryAtom);
  // resetQuery();
  // or
  // const setQuery = useSetAtom(queryAtom);
  // setQuery(RESET);
  ```
- **Relevance**: Useful for form fields, search inputs, or any state that needs a clear reset mechanism.

### Async Utilities (e.g., `loadable`)
- **Purpose**: `loadable` is a utility that takes an atom (often an async atom) and returns a new atom that provides the status of the promise (e.g., `loading`, `hasData`, `data`, `hasError`, `error`).
- **Usage**:
  ```typescript
  import { atom } from 'jotai';
  import { loadable } from 'jotai/utils';
  const asyncAtom = atom(async () => fetch('/api/data').then(res => res.json()));
  const loadableAtom = loadable(asyncAtom);
  // In component:
  // const value = useAtomValue(loadableAtom);
  // if (value.state === 'loading') ...
  // if (value.state === 'hasData') ... value.data
  ```
- **Relevance**: Simplifies handling loading and error states for asynchronous operations within components.

### `atomFamily`
- **Purpose**: A utility to create and manage a collection of related atoms, where each atom is identified by a parameter.
- **Usage**:
  ```typescript
  import { atom } from 'jotai';
  import { atomFamily } from 'jotai/utils';
  const todoAtomFamily = atomFamily((param: { id: number; text: string }) =>
    atom({ id: param.id, text: param.text, completed: false })
  );
  // const todo1Atom = todoAtomFamily({ id: 1, text: 'Buy milk' });
  ```
- **Relevance**: Useful for dynamic lists where each item has its own independent state. Atoms are created on demand and can be garbage collected.

### `atomWithLazy` (Conceptual - from Lazy Utilities)
- **Purpose**: While not explicitly detailed in the provided overview, "Lazy" utilities in Jotai typically involve creating atoms whose initial value or computation is deferred until the atom is first read. This can be useful for performance optimization, especially for expensive computations or atoms that depend on code-splitted modules.
- **Conceptual Usage**:
  ```typescript
  import { atom } from 'jotai';
  // Hypothetical or common pattern for a lazy utility
  // const lazyLoadedModuleAtom = atom(async () => {
  //   const module = await import('./heavy-module');
  //   return module.defaultValue;
  // });
  // Or a utility like:
  // import { atomWithLazy } from 'jotai/utils'; // Assuming such a utility
  // const lazyAtom = atomWithLazy(async (get) => {
  //   const data = await fetchSomeData();
  //   return processData(data);
  // });
  ```
- **Relevance**: Improves initial load time and performance by only computing or loading resources when they are actually needed. This is particularly beneficial in large applications or when dealing with heavy components/data.

## Relevant Extensions (Separate Packages)

These extensions provide additional atom types or functionalities and need to be installed separately.

### `jotai-immer` (`atomWithImmer`)
- **Package**: `jotai-immer` (requires `immer`)
- **Purpose**: Integrates Immer for simplified immutable updates, especially for atoms with complex or nested state.
- **Usage**:
  ```typescript
  import { atomWithImmer } from 'jotai-immer';
  const userAtom = atomWithImmer({ name: '', address: { city: '' } });
  // In component:
  // const setUser = useSetAtom(userAtom);
  // setUser(draft => { draft.address.city = 'New York'; });
  ```
- **Relevance**: Makes updating nested objects or arrays in atoms more concise and less error-prone.
- **Installation**: `npm install jotai-immer immer` or `yarn add jotai-immer immer`

### `jotai-location` (`atomWithLocation`, `atomWithHash`)
- **Package**: `jotai-location`
- **Purpose**: Creates atoms that synchronize their state with the browser's URL (query parameters via `atomWithLocation`, or hash via `atomWithHash`).
- **Usage**:
  ```typescript
  import { atomWithLocation } from 'jotai-location';
  const tabAtom = atomWithLocation({
    // options like queryParam, initialValue, etc.
  });
  ```
- **Relevance**: Extremely useful in Next.js for making UI state shareable via URL, bookmarkable, and integrated with browser history.
- **Installation**: `npm install jotai-location` or `yarn add jotai-location`

### `jotai-react-query` (`atomWithQuery`)
- **Package**: `jotai-react-query` (requires `@tanstack/react-query`)
- **Purpose**: Integrates Jotai with TanStack Query (formerly React Query), allowing you to create atoms that derive their state from queries.
- **Usage**:
  ```typescript
  import { atomWithQuery } from 'jotai-react-query';
  const postsAtom = atomWithQuery(get => ({
    queryKey: ['posts', get(userIdAtom)],
    queryFn: async ({ queryKey: [, userId] }) => fetchPosts(userId),
  }));
  ```
- **Relevance**: Combines Jotai's state management with TanStack Query's powerful data fetching, caching, and server state synchronization capabilities. While STATBUS uses SWR primarily, this pattern is good to be aware of for Jotai-centric data fetching.
- **Installation**: `npm install jotai-react-query @tanstack/react-query` or `yarn add jotai-react-query @tanstack/react-query`

### `jotai-cache` (`atomWithCache`)
- **Package**: `jotai-cache`
- **Purpose**: Provides atoms with built-in caching mechanisms, useful for memoizing expensive computations or fetched data that doesn't change often.
- **Relevance**: Can help optimize performance by avoiding redundant calculations or API calls.
- **Installation**: `npm install jotai-cache` or `yarn add jotai-cache`

### `jotai-effect` (`atomWithEffect`)
- **Package**: `jotai-effect`
- **Purpose**: Allows running side effects in response to an atom's lifecycle (mount, unmount, value change), similar to `React.useEffect` but for atoms.
- **Usage**:
  ```typescript
  import { atom } from 'jotai';
  import { atomWithEffect } from 'jotai-effect';
  const countAtom = atom(0);
  const loggerAtom = atomWithEffect(countAtom, (newValue, oldValue) => {
    console.log(`Count changed from ${oldValue} to ${newValue}`);
    return () => {
      console.log('Effect cleanup for countAtom');
    };
  });
  ```
- **Relevance**: Useful for managing side effects that are tightly coupled to an atom's state or lifecycle, such as logging, data synchronization, or setting up/tearing down event listeners.
- **Installation**: `npm install jotai-effect` or `yarn add jotai-effect`

### `jotai-eager` (`eagerAtom`, `soon`, `soonAll`)
- **Package**: `jotai-eager` (formerly `jotai-derive`)
- **Purpose**: Lets you build asynchronous data graphs without unnecessary suspensions. `eagerAtom` creates atoms where the read function is synchronous, and asynchronicity of dependencies is handled transparently. This helps manage "dual-natured" atoms (which can be sync or async) by acting on values as soon as they are available, preventing unnecessary deferring, recomputation, and potential micro-suspensions in React.
- **Core Primitive**: `eagerAtom`
  - The read function must be synchronous.
  - Dependencies (even async ones) are accessed via `get(someAtom)` without `await`.
  - The atom's value will be `T | Promise<T>`.
- **Usage**:
  ```typescript
  import { atom } from 'jotai';
  import { eagerAtom } from 'jotai-eager';

  const petsAtom = atom<Promise<string[]>>(async () => ['cat', 'dog', 'catfish']);
  const filterAtom = atom('cat');

  // filteredPetsAtom will be string[] | Promise<string[]>
  // It will be string[] if only filterAtom changes.
  // It will be Promise<string[]> if petsAtom is re-evaluated.
  const filteredPetsAtom = eagerAtom((get) => {
    const filter = get(filterAtom); // Regular sync access
    const pets = get(petsAtom);     // ✨ No await, even if petsAtom is async ✨
    return pets.filter(name => name.includes(filter));
  });
  ```
- **Key APIs within `eagerAtom`'s read function**:
    - `get(someAtom)`: Accesses dependency values. If `someAtom` is async and not yet resolved, `eagerAtom` handles the promise.
    - `get.all([atomA, atomB])`: Similar to `Promise.all`, but for atom dependencies. Useful for avoiding request waterfalls.
      ```typescript
      // const myMessages = eagerAtom((get) => {
      //   const [user, messages] = get.all([userAtom, messagesAtom]);
      //   return messages.filter((msg) => msg.authorId === user.id);
      // }); // => Atom<Message[] | Promise<Message[]>>
      ```
    - `get.await(promise)`: Awaits a regular (non-atom) Promise. The promise must be consistent across read function invocations.
      ```typescript
      // const statusAtom = eagerAtom((get) => {
      //   const statusPromise = get(currentInvoiceAtom).getStatus(); // => Promise<InvoiceStatus>
      //   const status = get.await(statusPromise);
      //   return status;
      // });
      ```
- **Handling `try/catch`**:
  Internal exceptions are used for async control flow. If you use `try/catch` inside an `eagerAtom`, you must rethrow `jotai-eager`'s specific errors:
  ```typescript
  import { eagerAtom, isEagerError } from 'jotai-eager';
  // const fooAtom = eagerAtom((get) => {
  //   try { /* ... */ } catch (e) {
  //     if (isEagerError(e)) { throw e; }
  //     // ... your error handling ...
  //   }
  // });
  ```
- **Advanced Usage (`soon`, `soonAll`)**:
  For more fine-grained control or when the purity of `eagerAtom`'s read function is too restrictive, `soon` and `soonAll` can be used for sync/async transformations.
  ```typescript
  import { soon, soonAll } from 'jotai-eager';
  // // Atom<RestrictedItem | null | Promise<RestrictedItem | null>>
  // const restrictedItemAtom = atom((get) => {
  //   return soon(
  //     soonAll(get(isAdminAtom), get(enabledAtom)),
  //     ([isAdmin, enabled]) =>
  //       isAdmin && enabled ? get(queryAtom) : null,
  //   );
  // });
  ```
- **Relevance**: Improves performance and UI stability when working with atoms that might resolve synchronously or asynchronously (dual-natured atoms). It's particularly useful when local cache updates might cause micro-suspensions or when unnecessary re-computation due to promise chaining is a concern. Avoids request waterfalls by allowing eager fetching of multiple async dependencies.
- **Installation**: `npm install jotai-eager` or `yarn add jotai-eager`

# create-svelte

Everything you need to build a Svelte project, powered by [`create-svelte`](https://github.com/sveltejs/kit/tree/master/packages/create-svelte).

## Setting up tools

Install a node manager, we recommend fnm (Fast Node Manager) https://github.com/Schniz/fnm
On mac and linux with:
```
curl -fsSL https://fnm.vercel.app/install | bash
```
On Windows with scoop (scoop.it) and
```
scoop install fnm
```

Install the recommended node version with
```
cd ui
fnm use
```

Install the pnpm package manager, that saves time and lots of disk
space.

```
corepack enable
corepack prepare pnpm@latest --activate
```

## Creating a project

If you're seeing this, you've probably already done this step. Congrats!

```bash
# create a new project in the current directory
pnpm create svelte@latest

# create a new project in my-app
pnpm create svelte@latest my-app
```

## Developing

Once you've created a project and installed dependencies with `pnpm install` (or `ppnpm install` or `yarn`), start a development server:

```bash
pnpm run dev

# or start the server and open the app in a new browser tab
pnpm run dev -- --open
```

## Building

To create a production version of your app:

```bash
pnpm run build
```

You can preview the production build with `pnpm run preview`.

> To deploy your app, you may need to install an [adapter](https://kit.svelte.dev/docs/adapters) for your target environment.

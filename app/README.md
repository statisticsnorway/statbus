### Getting Started

### Prerequisites

Ensure you have the correct Node.js version. We recommend using `fnm` (Fast Node Manager) for managing Node.js versions. You can install `fnm` by following the instructions on the [fnm GitHub page](https://github.com/Schniz/fnm).

Once `fnm` is installed, use it to switch to the required Node.js version.

```bash
fnm use
```

Additionally, enable `pnpm` using Corepack, which is included with Node.js:

```bash
corepack enable pnpm
```
To ensure you are using the latest version of `pnpm`, you can upgrade it with:

```bash
corepack use pnpm@latest
```

### Install Dependencies

```bash
pnpm install
```

By default the ../.env file is used to contact your locally running
Supabase instance. If you need to override that you can create
an `.env.local` file in the root of the project and add the following,
with adjustments:

```env
SERVER_REST_URL=http://localhost:3001
NEXT_PUBLIC_BROWSER_REST_URL=http://localhost:3001
NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=Development
NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=dev
VERSION=0.0.1.local
SEQ_SERVER_URL=http://localhost:5341
SEQ_API_KEY=unused-when-running-locally
```

# The connection uses direct PostgREST with our custom auth system
# We use Supabase client libraries for type safety, but not Supabase services
# The SEQ_API_KEY must match the server you are connecting to.

### Run the Development Server

```bash
pnpm run dev
```

### View Logs

To view the logs, run the following command to start Seq, a log server:

```bash
docker compose up
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

### VSCode Debugging

To have VSCode automatically attach to your running Node.js instances, run the command:
`code --enable-proposed-api ms-vscode.node-debug`.

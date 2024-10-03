### Getting Started

### Prerequisites

Ensure you have the correct Node.js version. We recommend using `fnm` (Fast Node Manager) for managing Node.js versions. You can install `fnm` by following the instructions on the [fnm GitHub page](https://github.com/Schniz/fnm).

Once `fnm` is installed, use it to switch to the required Node.js version:

```bash
fnm use
```

### Install Dependencies

```bash
npm i
```

Next, create a `.env.local` file in the root of the project and add the following:

```env
VERSION=0.0.1.local
LOG_SERVER=http://localhost:5341

SUPABASE_ANON_KEY={anon_key}
SUPABASE_URL={supabase_url}
```

### Run the Development Server

```bash
npm run dev
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

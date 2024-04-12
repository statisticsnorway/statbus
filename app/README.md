### Getting Started

First, install the dependencies:

```bash
npm i
```

Then, create a `.env.local` file in the root of the project and add the following:

```env
VERSION=0.0.1.local
LOG_SERVER=http://localhost:5341

SUPABASE_ANON_KEY={anon_key}
SUPABASE_URL={supabase_url}
```

Lastly, run the development server:

```bash
npm run dev
```

To view the logs, run the following command to start Seq, a log server:

```bash
docker compose up
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

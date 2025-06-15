// next.config.js
const dotenv = require('dotenv');

if (process.env.NODE_ENV !== 'production' && !process.env.ENV_LOADED) {
  const envFilePath = '../.env';
  dotenv.config({ path: envFilePath });
  process.env.ENV_LOADED = 'true';
  console.log(`Development Environment file ${envFilePath} loaded successfully.`);
}

const isDevelopment = process.env.NODE_ENV === 'development';

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Output a server running js file that does SSR (Server Side Rendering)
  // as opposed to 'export' that exports static HTML files.
  output: 'standalone',
  reactStrictMode: true,
};

// Add API proxying in development mode
if (isDevelopment) {
  // In local development (e.g., `pnpm run dev`), Next.js runs on localhost:3000 (or $PORT).
  // Client-side API calls should target this Next.js dev server.
  // The Next.js dev server will then proxy these /rest/* calls to Caddy.

  // 1. Determine Caddy's URL (where Next.js should proxy to).
  //    NEXT_PUBLIC_BROWSER_REST_URL from .env (set by manage.cr) points to Caddy.
  const caddyUrlFromEnv = process.env.NEXT_PUBLIC_BROWSER_REST_URL;
  if (!caddyUrlFromEnv) {
    console.error(
      "ERROR: NEXT_PUBLIC_BROWSER_REST_URL is not set in .env. " +
      "This is required for local development rewrites to Caddy. " +
      "Please run './devops/manage-statbus.sh generate-config'."
    );
    throw new Error('NEXT_PUBLIC_BROWSER_REST_URL is not set for local development proxy.');
  }
  const caddyRewriteTarget = caddyUrlFromEnv.startsWith('http')
    ? caddyUrlFromEnv
    : `http://${caddyUrlFromEnv}`;

  // 2. Override NEXT_PUBLIC_BROWSER_REST_URL for client-side use.
  //    It should point to the Next.js dev server itself.
  const localAppPort = process.env.PORT || 3000;
  const localAppUrl = `http://localhost:${localAppPort}`;
  
  console.log(
    `Local Development: Client-side API calls (NEXT_PUBLIC_BROWSER_REST_URL) will use: ${localAppUrl}`
  );
  process.env.NEXT_PUBLIC_BROWSER_REST_URL = localAppUrl;

  // 3. Configure Next.js rewrites to proxy /rest/* from localAppUrl to caddyRewriteTarget.
  console.log(
    `Local Development: Next.js server will proxy API calls from ${localAppUrl}/rest/* to ${caddyRewriteTarget}/rest/*`
  );
  nextConfig.rewrites = async () => {
    return [
      {
        source: '/rest/:path*',
        destination: `${caddyRewriteTarget}/rest/:path*`,
      },
    ];
  };
}

module.exports = nextConfig;

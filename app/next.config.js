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
  // Get the PostgREST URL from environment and ensure it has http:// prefix
  const serverApiUrl = process.env.SERVER_API_URL;
  
  if (!serverApiUrl) {
    console.error('SERVER_API_URL environment variable is not set');
    throw new Error('SERVER_API_URL environment variable is required for development mode');
  }
  
  // Ensure the URL has http:// prefix
  const SERVER_API_URL = serverApiUrl.startsWith('http') 
    ? serverApiUrl 
    : `http://${serverApiUrl}`;
  
  nextConfig.rewrites = async () => {
    console.log(`Development proxy configured: /postgrest/* -> ${SERVER_API_URL}/*`);
    return [
      // Proxy all /postgrest/* requests to the PostgREST server
      { source: '/postgrest/:path*', destination: `${SERVER_API_URL}/postgrest/:path*` },
    ];
  };
}

module.exports = nextConfig;

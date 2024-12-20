// next.config.js
const dotenv = require('dotenv');

if (process.env.NODE_ENV !== 'production' && !process.env.ENV_LOADED) {
  const envFilePath = '../.env';
  dotenv.config({ path: envFilePath });
  process.env.ENV_LOADED = 'true';
  console.log(`Development Environment file ${envFilePath} loaded successfully.`);
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Output a server running js file that does SSR (Server Side Rendering)
  // as opposed to 'export' that exports static HTML files.
  output: 'standalone',
  reactStrictMode: true,
};

module.exports = nextConfig;

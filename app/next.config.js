// next.config.js
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Output a server running js file that does SSR (Server Side Rendering)
  // as opposed to 'export' that exports static HTML files.
  output: 'standalone',
  // Disable double rendering of everything, that is more annoying
  // than the other checks/benefits that strict mode enables.
  reactStrictMode: false,
};

module.exports = nextConfig;

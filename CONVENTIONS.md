This is a Supabase + Next.js project using modern PostgreSQL (16+).
Next.js files are in the app/ directory with TypeScript.
Legacy code is in legacy/ for reference only.
The app runs server-side and client-side with SSR, using Next.js 14 in app/src/{app,api,...} directories.
Deployed on custom servers behind Caddy with HTTPS.

 • Use named exports for HTTP methods.
 • Use route.ts for all pages.
 • Handle responses with NextResponse.
 • Organize under app/api to match endpoints.
 • Avoid default exports.
 • Styling: Tailwind CSS.
 • Testing: Jest and ts-jest.
 • Build/Deployment: Standard Next.js scripts in package.json.
 • Use React Context/hooks; organize in context/ and hooks/.
 • Group components by feature in components/.
 • Use TypeScript; define types in .d.ts or locally.
 • Use functional components with hooks.
 • Use layout.tsx in app/ for global providers, not _app.tsx. 
 • Use an app directory structure (not pages).

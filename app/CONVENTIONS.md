This is a Supabase + Next.js project using modern PostgreSQL (16+).
Next.js files are in the app/ directory with TypeScript.
Legacy code is in legacy/ for reference only.
The app runs server-side and client-side with SSR, using Next.js 14 in app/src/{app,api,...} directories.
Deployed on custom servers behind Caddy with HTTPS.

 • Use named exports for HTTP methods.
 • Use destructuring for imports.
 • Use route.ts for all pages and API routes in app/.
 • Handle responses with NextResponse.
 • Organize under app/api to match endpoints.
 • Avoid default exports.
 • Styling: Tailwind CSS.
 • Component Library: shadcn/ui
 • Testing: Jest and ts-jest.
 • Build/Deployment: Standard Next.js scripts in package.json.
 • Use React Context/hooks; organize in context/ and hooks/.
 • Group components by feature in components/.
 • Use TypeScript; define types in .d.ts or locally.
 • Use functional components with hooks.
 • Use App Routing(app directory structure) (not Pages Router).
 • Use layout.tsx in app/ for global providers, not `_app.tsx`. 

When CWD is the app dir then shell commands must remove the initial 'app/' from paths.

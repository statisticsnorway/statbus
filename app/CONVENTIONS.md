This document outlines conventions for the Next.js (15) application part of the STATBUS project.
For general project, SQL, and infrastructure conventions, see `CONVENTIONS.md` in the project root.

Next.js files are in the app/ directory with TypeScript.
The app runs server-side and client-side with SSR, using Next.js 15 in app/src/{app,api,...} directories.
The new Next.js promise pattern is used for params.

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
 • Use a Fail Fast Approach for functionality that is supposed to work.
 • Have a single source of truth in the codebase - avoid duplicate stores for the same data.
 • When refactoring, complete the full migration without compatibility layers.
 • Fail fast and provide error or debug information to fix, don't mask or workaround issues.
 • Think from first principles.
 • Document by having clear code - any internal comments about your thought process should not be left in the code.
 
## Routing System
This project uses **App Routing** with the `app/` directory structure. Do not use the Pages Router.

### Key Points:
- Use hooks from `next/navigation` such as `usePathname` and `useSearchParams` for navigation and route handling.
- Organize routes using `route.ts` files for pages and API routes.
- Handle responses with `NextResponse`.
 • Use layout.tsx in app/ for global providers, not `_app.tsx`.

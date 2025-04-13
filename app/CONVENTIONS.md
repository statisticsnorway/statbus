This is a PostgreSQL(17+) + PostgREST(12+) + Next.js project.
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
 • Use a Fail Fast Approach for functionality that is supposed to work.
 • Try to have a single source of truth in the codebase.
## Routing System
This project uses **App Routing** with the `app/` directory structure. Do not use the Pages Router.

### Key Points:
- Use hooks from `next/navigation` such as `usePathname` and `useSearchParams` for navigation and route handling.
- Organize routes using `route.ts` files for pages and API routes.
- Handle responses with `NextResponse`.
 • Use layout.tsx in app/ for global providers, not `_app.tsx`. 

When CWD is the app dir then shell commands must remove the initial 'app/' from paths.

## SQL
When defining functions and procedures use the function name as part of the literal string quote
for the body and specify the LANGUAGE before the body, so one knows how to parse it up front.
Ensure that parameters are documentation friendly, and therefore always use the long form
to avoid ambiguity.
```
CREATE FUNCTION public.example(email text) RETURNS void LANGUAGE plpgsql AS $example$
BEGIN
  ...
  SELECT * FROM ...
  WHERE email = example.email
  ...
END;
$$;

When calling functions with multiple arguments (3+), use named arguments for clarity, arg1 => val1, arg2 => val2, etc.

### SQL Testing
Is done with pg_regress with test/ as base.
Run with `./devops/manage-statbus.sh test [all|xx_the_test_name]`.

# Next.js and Cookie Handling

This document outlines how cookies are managed within this Next.js 15 application, particularly in conjunction with Supabase for authentication and session management. Understanding these patterns is crucial for maintaining security and correct application behavior.

## Core Principles of Cookie Handling in Next.js (App Router)

The primary challenge with cookies in Next.js (App Router) is that **Server Components and server-rendered Pages cannot directly set cookies.** They can *read* incoming cookies, but setting cookies must occur before the response headers are sent. Since Server Components often stream responses, modifications to cookies must happen in Middleware, Server Actions, or API Route Handlers.

In Next.js 15, the `cookies()` function from `next/headers` is **asynchronous**. You must use `async/await` or React's `use()` to access the cookie store. Using `cookies()` in a Server Component, Layout, or Page will opt the route into [dynamic rendering](https://nextjs.org/docs/app/getting-started/partial-prerendering#dynamic-rendering).

Our application uses different strategies for cookie handling based on the execution context:

### 1. Middleware (`app/src/middleware.ts`)

-   **Primary Role:** Middleware is the **most reliable and central place to manage (read and write) session cookies.** It acts as a gatekeeper for requests.
-   **Mechanism:**
    -   It runs before the request reaches Server Components or Pages.
    -   It operates on `NextRequest` and can modify/return a `NextResponse`.
    -   The core idea is to use `NextRequest` to read incoming cookies and `NextResponse` to set outgoing cookies.
    -   An authentication client used here should be configurable to:
        1.  Read cookies via `request.cookies.get(name)` or `request.cookies.getAll()`.
        2.  Write cookies via `response.cookies.set(name, value, options)`.
        3.  **Crucially**, if a cookie (like a session token) is set or updated by the auth client, it should also be set on the *incoming* `request.cookies` collection (e.g., `request.cookies.set(name, value)`). This makes the updated cookie immediately available to any subsequent Server Components or SSR Pages within the same request lifecycle. This is often achieved by modifying the `request.headers` for the `NextResponse.next({ request: { headers: updatedHeaders }})`.
        4.  Enable features like session detection from URL, session persistence (writing cookies), and automatic token refresh, as middleware is the correct context for these side effects.

    ```typescript
    // Example: app/src/middleware.ts
    import { NextResponse, type NextRequest } from 'next/server';
    // import { initializeAuthClientForMiddleware } from './your-auth-utils'; // Your custom utility

    export async function middleware(request: NextRequest) {
      // It's good practice to clone headers if you intend to modify them for the ongoing request.
      const requestHeaders = new Headers(request.headers);
      
      // Create a response object that can be modified.
      // Pass the original request to NextResponse.next() to preserve its properties.
      // If request headers need to be modified for downstream handlers (e.g. SSR pages),
      // they should be set on the request object passed to NextResponse.next().
      let response = NextResponse.next({
        request: {
          headers: requestHeaders,
        },
      });

      // --- Hypothetical Auth Client Initialization & Usage ---
      // const authClient = await initializeAuthClientForMiddleware(
      //   { // Cookie getter
      //     get: (name) => request.cookies.get(name)?.value,
      //     getAll: () => request.cookies.getAll(),
      //   },
      //   { // Cookie setter
      //     set: (name, value, options) => {
      //       request.cookies.set(name, value, options); // Make available for current request lifecycle
      //       response.cookies.set(name, value, options); // Send back to browser
      //     },
      //   },
      //   { /* other auth client options like autoRefreshToken: true, persistSession: true */ }
      // );
      // const { session } = await authClient.getSession();
      // --- End Hypothetical Auth Client ---

      // Example: Reading a cookie directly
      const themeCookie = request.cookies.get('theme');
      if (themeCookie) {
        console.log('Theme from middleware:', themeCookie.value);
      }

      // Example: Setting a cookie to be sent to the browser
      // response.cookies.set('middleware-cookie', 'set-by-middleware', { path: '/' });

      // --- Example: Auth redirection ---
      // if (!session && !request.nextUrl.pathname.startsWith('/login')) {
      //   const loginUrl = new URL('/login', request.url);
      //   // Preserve existing headers on the response when redirecting
      //   const redirectResponse = NextResponse.redirect(loginUrl, { headers: response.headers });
      //   // Copy over any cookies that might have been set on `response` before redirecting
      //   response.cookies.getAll().forEach(cookie => {
      //     redirectResponse.cookies.set(cookie.name, cookie.value, cookie);
      //   });
      //   return redirectResponse;
      // }

      return response;
    }

    export const config = {
      matcher: [
        /*
         * Match all request paths except for the ones starting with:
         * - _next/static (static files)
         * - _next/image (image optimization files)
         * - favicon.ico (favicon file)
         * - api/auth (example: your auth API routes like login, logout, callback)
         * - Other public paths
         */
        "/((?!_next/static|_next/image|favicon.ico|api/auth).*)",
      ],
    };
    ```

### 2. Server Actions & API Routes (Route Handlers)

-   **Role:** Can read and write cookies. Suitable for operations triggered by client interactions (e.g., form submissions, API calls from client components) that need to modify cookie state.
-   **Mechanism:**
    -   Import `cookies` from `next/headers`.
    -   Get the cookie store: `const cookieStore = cookies();`. This store allows both reading and writing.
    -   An authentication client used here should be configurable to:
        1.  Read cookies via `cookieStore.get(name)`.
        2.  Write cookies via `cookieStore.set(name, value, options)`. Next.js handles sending these `Set-Cookie` headers correctly when the Server Action or API Route completes.
        3.  Enable features like session detection from URL, session persistence, and automatic token refresh.

    ```typescript
    // Example: app/auth/login/route.ts (API Route Handler)
    // Or: app/actions/auth-actions.ts (Server Action)
    "use server"; // Required for Server Actions

    import { cookies } from 'next/headers';
    // import { initializeAuthClientForApi } from '../your-auth-utils'; // Your custom utility
    import { type NextRequest, NextResponse } from 'next/server';


    // Example for an API Route Handler
    export async function POST(request: NextRequest) {
      const cookieStore = cookies();
      // const body = await request.json();
      // const { email, password } = body;

      // --- Hypothetical Auth Client Initialization & Usage ---
      // const authClient = await initializeAuthClientForApi(
      //   { // Cookie getter
      //     get: (name) => cookieStore.get(name)?.value,
      //     getAll: () => cookieStore.getAll().map(c => ({name: c.name, value: c.value})), // Adapt to your auth client needs
      //   },
      //   { // Cookie setter
      //     set: (name, value, options) => cookieStore.set(name, value, options),
      //   },
      //   { /* other auth client options */ }
      // );
      // const { error } = await authClient.login(email, password);
      // if (error) {
      //   return NextResponse.json({ error: error.message }, { status: 401 });
      // }
      // --- End Hypothetical Auth Client ---

      // Example: Reading a cookie
      const existingSession = cookieStore.get('session-id');
      if (existingSession) {
        console.log('Existing session ID from API route:', existingSession.value);
      }

      // Example: Setting a cookie (authClient would typically do this)
      // cookieStore.set('session-id', 'new-session-value', { httpOnly: true, path: '/' });

      // return NextResponse.json({ message: 'Login successful' });
      return NextResponse.json({ message: 'Operation successful' });
    }

    // Example for a Server Action
    // export async function loginUser(formData: FormData) {
    //   const cookieStore = await cookies(); // cookies() is async
    //   const email = formData.get('email') as string;
    //   const password = formData.get('password') as string;
    //
    //   // --- Hypothetical Auth Client (similar to above) ---
    //   // const authClient = await initializeAuthClientForApi(...);
    //   // const { error, data } = await authClient.login(email, password);
    //   // if (error) return { error: error.message };
    //   //
    //   // Example: Setting access and refresh tokens with specific paths
    //   // if (data.session) {
    //   //   cookieStore.set('access-token', data.session.access_token, { httpOnly: true, secure: true, path: '/', sameSite: 'lax' });
    //   //   cookieStore.set('refresh-token', data.session.refresh_token, { httpOnly: true, secure: true, path: '/api/auth/refresh', sameSite: 'strict' });
    //   // }
    //   // return { success: true, user: data.user };
    //   console.log('Server action: read cookie', cookieStore.get('some-cookie')?.value);
    //   cookieStore.set('action-cookie', 'set-by-action', {path: '/'});
    //   return { success: true };
    // }

    // Example for deleting cookies in a Server Action
    // export async function logoutUser() {
    //   const cookieStore = await cookies();
    //   // Method 1: Direct delete
    //   cookieStore.delete('access-token');
    //   cookieStore.delete('refresh-token');
    //
    //   // Method 2: Set empty value with immediate expiry (alternative for one cookie)
    //   // cookieStore.set('access-token', '', { maxAge: 0 });
    //
    //   // Method 3: Clear all cookies (use with caution)
    //   // cookieStore.clear();
    //   return { success: true };
    // }
    ```

### 3. Server Components & SSR Pages (e.g., `app/src/app/.../page.tsx`)

-   **Role:** Can reliably *read* cookies. They **should not** attempt to *write* cookies directly, as this can lead to errors or unexpected behavior due to response streaming.
-   **Mechanism:**
    -   Import `cookies` from `next/headers`.
    -   Get the cookie store: `const cookieStore = cookies();`.
    -   An authentication client used here should be configured for **read-only cookie operations**:
        1.  Read cookies via `cookieStore.get(name)`.
        2.  The cookie "setter" provided to the auth client should ideally throw an error or be a no-op to prevent accidental writes.
        3.  Disable features like session detection from URL, session persistence, and automatic token refresh. These should have been handled by middleware or an explicit Server Action/API call.

    ```typescript
    // Example: app/dashboard/page.tsx (Server Component/SSR Page)
    import { cookies } from 'next/headers';
    // import { initializeAuthClientForSSR } from '../your-auth-utils'; // Your custom utility

    export default async function DashboardPage() {
      const cookieStore = await cookies(); // cookies() is async

      // --- Hypothetical Auth Client Initialization & Usage (Read-Only for Cookies) ---
      // const authClient = await initializeAuthClientForSSR(
      //   { // Cookie getter
      //     get: (name) => cookieStore.get(name)?.value,
      //     getAll: () => cookieStore.getAll().map(c => ({name: c.name, value: c.value})),
      //   },
      //   { // Cookie setter (should be no-op or throw)
      //     set: (name, value, options) => {
      //       console.warn(`Attempted to set cookie '${name}' in SSR context. This is not allowed.`);
      //       // throw new Error("Cannot set cookies in SSR pages/Server Components directly.");
      //     },
      //   },
      //   { /* auth client options like autoRefreshToken: false, persistSession: false */ }
      // );
      // const { user } = await authClient.getUser();
      // if (!user) {
      //   // redirect('/login'); // Use next/navigation for redirects in Server Components
      // }
      // --- End Hypothetical Auth Client ---

      // Example: Reading a cookie directly
      const userPreference = cookieStore.get('user-preference');
      console.log('User preference from SSR page:', userPreference?.value);

      // DO NOT ATTEMPT TO WRITE COOKIES HERE:
      // cookieStore.set('some-ssr-cookie', 'value'); // This will likely cause an error or not work as expected.

      // return <DashboardLayout user={user} preferences={userPreference?.value} />;
      return (
        <main>
          <h1>Dashboard</h1>
          <p>User preference: {userPreference?.value || 'not set'}</p>
        </main>
      );
    }
    ```

### 4. Static Site Generation (SSG)

-   **Role:** No access to request-specific cookies during the build process. Pages are generated at build time without knowledge of individual user requests.
-   **Mechanism:**
    -   The `cookies()` function from `next/headers` is not available or meaningful in the context of SSG data fetching at build time.
    -   An authentication client used here (e.g., for fetching global, non-user-specific data) should be configured:
        1.  To not attempt any cookie operations (reads or writes). Cookie getters should return empty/null, and setters should be no-ops or throw errors.
        2.  To disable all session-related features (session detection, persistence, token refresh).

    ```typescript
    // Example: app/about/page.tsx (Statically Generated Page)
    // import { initializeAuthClientForSSG } from '../your-auth-utils'; // Your custom utility

    export default async function AboutPage() {
      // cookies() is not typically used in SSG data fetching at build time
      // as there's no per-request cookie context.

      // --- Hypothetical Auth Client Initialization & Usage (No Cookie Access) ---
      // const authClient = await initializeAuthClientForSSG(
      //   { get: () => undefined, getAll: () => [] }, // No-op cookie getter
      //   { set: () => console.warn("Attempted to set cookie in SSG context.") }, // No-op cookie setter
      //   { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false }
      // );
      // const globalSettings = await authClient.getGlobalSettings(); // Example: fetching non-user data
      // --- End Hypothetical Auth Client ---

      // The cookies() function from 'next/headers' would not provide request-specific
      // cookies at build time.
      // console.log(cookies().get('any-cookie')); // This would error or be empty during build.

      // return <AboutContent settings={globalSettings} />;
      return (
        <main>
          <h1>About Us</h1>
          <p>This page is statically generated.</p>
        </main>
      );
    }
    ```

## Security Considerations

-   **HttpOnly:** Sensitive cookies (e.g., session tokens) should always be `HttpOnly` to prevent access from client-side JavaScript, mitigating XSS risks.
-   **Secure:** In production environments (HTTPS), cookies should have the `Secure` attribute, ensuring they are only transmitted over encrypted connections.
-   **SameSite:** Configure the `SameSite` attribute (e.g., `Lax` or `Strict`) to protect against Cross-Site Request Forgery (CSRF) attacks. `Lax` is a good default for most access tokens. For refresh tokens, `Strict` is often preferred.
-   **Path:**
    -   For general-purpose cookies or access tokens that need to be sent with most requests to your domain, `Path=/` is common.
    -   **Refresh Token Path (Critical Security Measure):** Refresh tokens are highly sensitive and long-lived. They should **only** be sent to the specific endpoint responsible for exchanging them for new access tokens (e.g., `/api/auth/refresh`). Therefore, the `Path` attribute for refresh token cookies **must be strictly scoped** to this endpoint (e.g., `path: '/api/auth/refresh'`). Setting `Path=/` for a refresh token is a security risk as it would cause the browser to send this sensitive token with every request to your domain, increasing its exposure.
-   **Domain:** Be mindful of the `Domain` attribute, especially in multi-subdomain scenarios.
-   **MaxAge/Expires:** Define appropriate lifetimes for cookies. Access tokens should have short lifespans, while refresh tokens will have longer ones. Session cookies (no `MaxAge` or `Expires`) are cleared when the browser closes.
-   **Cookie Deletion Constraints:** When using `cookies().delete(name)` (or `cookies().clear()`), be aware that:
    -   These methods must be called from a Server Action or Route Handler.
    -   For successful deletion, the cookie must belong to the same domain from which `delete()` is called. If the cookie was set with a specific domain, `delete()` must be able to operate on that domain. For wildcard domains, the specific subdomain must be an exact match.
    -   The code executing `delete()` must be on the same protocol (HTTP or HTTPS) as the cookie you intend to delete.
-   **Other Options:** The `cookies().set()` method supports other options like `priority`, `encode` (for custom value encoding), and `partitioned` (for CHIPS). Refer to [MDN docs on cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies) and the [Next.js `cookies()` documentation](https://nextjs.org/docs/app/api-reference/functions/cookies#options) for details.
-   Use a centralized utility or configuration (e.g., a hypothetical `app/src/utils/cookieOptions.ts`) to define and apply these security attributes consistently for cookies set by your application or auth client.

## Summary of Project's Cookie Strategy

This project employs a context-aware cookie management strategy:
-   **Middleware is paramount** for session management and ensuring cookie consistency across the request/response lifecycle, especially for operations like token refresh that need to reflect immediately for SSR.
-   Employ **dedicated auth client initialization strategies or wrappers tailored for each Next.js context** (Middleware, API/Server Actions, SSR, SSG). These wrappers should correctly configure the auth client's cookie handling and session management features (like token refresh, session persistence) according to the capabilities and limitations of each context.
-   Direct cookie writing is deliberately **prevented or strongly discouraged in Server Components and SSR page rendering** to avoid common Next.js pitfalls. Modifications should occur via Middleware or Server Actions/API Routes.
-   Security attributes for cookies are managed centrally and consistently.

By adhering to these patterns, the application ensures that cookie operations are performed correctly within the Next.js request/response lifecycle, maintaining session integrity and security regardless of the chosen authentication backend.

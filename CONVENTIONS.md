This is a Supbase + Next.js project.
The SQL code is modern Postgresql (16+).
The Next.js files are in the "app/" directory and use TypeScript.
The old legacy code is in "legacy/" and is for reference only.
Use a functional coding style.
The Next.js app runs both server side and client side with SSR.
Next.js 14 is used with traditional app/src/{app,api,...} directories.
The project is deployed on our custom servers and runs behind Caddy running HTTPS.
• Use named exports for HTTP methods.
• Use route.ts for all pages.
• Handle responses with NextResponse.
• Organize under app/api to match endpoints.
• Avoid default exports.
• Styling: Uses Tailwind CSS.
• Testing: Uses Jest and ts-jest.
• Build/Deployment: Standard Next.js scripts in package.json.
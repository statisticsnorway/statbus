import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "@/app/globals.css";
import { ReactNode, Suspense } from "react";
import Navbar, { NavbarSkeleton } from "@/components/navbar";
import { cn } from "@/lib/utils";
import { CommandPalette } from "@/components/command-palette/command-palette";
import { Toaster } from "@/components/ui/toaster";
import Footer, { FooterSkeleton } from "@/components/footer";
import GlobalErrorReporter from "@/app/global-error-reporter";
import PopStateHandler from "@/components/PopStateHandler";
import { UpgradeMaintenanceGuard } from "@/components/upgrade-maintenance-guard";
import { NuqsAdapter } from "nuqs/adapters/next/app";
import { JotaiAppProvider } from '@/atoms/JotaiAppProvider';
import { DebugInspector } from '@/components/dev/DebugInspector';
import { headers } from "next/headers";
import type { StatbusConfig } from "@/lib/statbus-config";

// Force dynamic rendering — layout injects window.__STATBUS_CONFIG__ from
// process.env at request time. Without this, Next.js caches the HTML shell
// at build time, freezing config values until the next deploy.
export const dynamic = 'force-dynamic';

const inter = Inter({ subsets: ["latin"] });

const slotName = process.env.PUBLIC_DEPLOYMENT_SLOT_NAME || "";

export const metadata: Metadata = {
  title: {
    template: `${slotName} Statbus | %s`,
    default: `${slotName} Statbus`,
  },
  description: "Simple To Use, Simple To Understand, Simply useful!",
};

export default async function RootLayout({
  children,
}: {
  readonly children: ReactNode;
}) {
  const headersList = await headers();
  const pathname = headersList.get("x-invoke-path") || "";
  const isReferencePage = pathname.startsWith('/jotai-state-management-reference');

  // Runtime config injected into HTML — client code reads from window.__STATBUS_CONFIG__.
  // PUBLIC_* env vars are set by docker-compose and read server-side at request time.
  const config: StatbusConfig = {
    browserRestUrl: process.env.PUBLIC_BROWSER_REST_URL || "",
    deploymentSlotName: process.env.PUBLIC_DEPLOYMENT_SLOT_NAME || "",
    deploymentSlotCode: process.env.PUBLIC_DEPLOYMENT_SLOT_CODE || "",
    debug: process.env.PUBLIC_DEBUG === "true",
    version: process.env.PUBLIC_STATBUS_VERSION || "",
    // Short-form (8-char) commit_short for display in footer / status —
    // sourced from PUBLIC_STATBUS_COMMIT_SHORT which is the name written
    // by `./sb config generate` (see cli/internal/config/config.go). Rc.63:
    // length suffix dropped from the env-var name — there's only one
    // short form (8 chars, documented at the Go helper). The property
    // name stays short ("commit") because this object is display-only;
    // no equality comparison ever reads it.
    commit: process.env.PUBLIC_STATBUS_COMMIT_SHORT || "",
  };

  return (
    <html lang="en" className="h-full bg-white">
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `window.__STATBUS_CONFIG__=${JSON.stringify(config)}`,
          }}
        />
      </head>
      <body
        className={cn(
          isReferencePage ? "" : "grid min-h-full grid-rows-[auto_1fr_auto]",
          "font-sans antialiased",
          inter.className
        )}
      >
        {isReferencePage ? (
          children
        ) : (
          <JotaiAppProvider>
            <NuqsAdapter>
              {/* RootLayoutClient wrapper removed, its children are now direct children of JotaiAppProvider */}
            {/* Main application content, now under Jotai's Provider and Suspense */}
            <Suspense fallback={
              <>
                {/* This fallback is for the initial static shell or while JotaiAppProvider's Suspense is active. */}
                  <NavbarSkeleton />
                  <div className="flex-grow p-4"><div>Loading application data...</div></div> {/* Placeholder for children */}
                  <FooterSkeleton />
                  <Toaster />
                  <CommandPalette />
                </>
              }>
                {/* ServerBaseDataProvider has been removed.
                    State management and initialization are now handled by JotaiAppProvider's client-side logic. */}
                <UpgradeMaintenanceGuard />
                <PopStateHandler />
                <Suspense fallback={<NavbarSkeleton />}>
                  <Navbar />
                </Suspense>
                {children}
                <CommandPalette />
                <Toaster />
                <Suspense fallback={<FooterSkeleton />}>
                  <Footer />
                </Suspense>
              </Suspense>
            {/* End of content previously in RootLayoutClient */}
            <GlobalErrorReporter />
            {/* DebugInspector is always rendered, and decides its own visibility */}
            <Suspense fallback={null}>
              <DebugInspector />
            </Suspense>
            </NuqsAdapter>
          </JotaiAppProvider>
        )}
      </body>
    </html>
  );
}

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

const inter = Inter({ subsets: ["latin"] });

const slotName = process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME || "";

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

  // Runtime config injected into HTML — client code reads from window.__STATBUS_CONFIG__
  // instead of process.env.NEXT_PUBLIC_*, avoiding build-time inlining and cache staleness.
  const config: StatbusConfig = {
    browserRestUrl: process.env.NEXT_PUBLIC_BROWSER_REST_URL || "",
    deploymentSlotName: process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME || "",
    deploymentSlotCode: process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE || "",
    debug: process.env.NEXT_PUBLIC_DEBUG === "true",
    version: process.env.NEXT_PUBLIC_STATBUS_VERSION || "",
    commit: process.env.NEXT_PUBLIC_STATBUS_COMMIT || "",
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

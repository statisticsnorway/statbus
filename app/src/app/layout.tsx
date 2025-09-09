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
import { NuqsAdapter } from "nuqs/adapters/next/app";
import { JotaiAppProvider } from '@/atoms/JotaiAppProvider';
import { DebugInspector } from '@/components/dev/DebugInspector';
import { deploymentSlotName } from "@/lib/deployment-variables";
import { headers } from "next/headers";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: {
    template: `${deploymentSlotName} Statbus | %s`,
    default: `${deploymentSlotName} Statbus`,
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

  return (
    <html lang="en" className="h-full bg-white">
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

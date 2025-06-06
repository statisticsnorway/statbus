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
import { ServerBaseDataProvider } from "@/app/BaseDataServer";
import { AuthProvider } from "@/context/AuthContext";
import { TimeContextProvider } from "@/app/time-context";
import { deploymentSlotName } from "@/lib/deployment-variables";
import RootLayoutClient from "./RootLayoutClient";

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
  
  return (
    <html lang="en" className="h-full bg-white">
      <body
        className={cn(
          "grid min-h-full grid-rows-[auto_1fr_auto] font-sans antialiased",
          inter.className
        )}
      >
        <AuthProvider>
          <RootLayoutClient>
            {/* Wrap ServerBaseDataProvider and its children in Suspense */}
            <Suspense fallback={
              <>
                {/* This fallback will be rendered for the initial static shell 
                    or while ServerBaseDataProvider is resolving on dynamic routes.
                    It should include basic layout structure if possible, 
                    or at least NavbarSkeleton and FooterSkeleton. */}
                <NavbarSkeleton />
                <div className="flex-grow p-4"><div>Loading application data...</div></div> {/* Placeholder for children */}
                <FooterSkeleton />
                <Toaster /> {/* Toaster can be outside if it doesn't depend on suspended data */}
                <CommandPalette /> {/* CommandPalette might also be okay outside */}
              </>
            }>
              <ServerBaseDataProvider>
                {/* TimeContextProvider and its children depend on BaseDataContext from ServerBaseDataProvider */}
                <TimeContextProvider>
                  <PopStateHandler />
                  {/* Navbar and Footer are already Suspense-wrapped, which is good.
                      They will use their own skeletons if ServerBaseDataProvider resolves 
                      but their specific data is still loading. */}
                  <Suspense fallback={<NavbarSkeleton />}>
                    <Navbar />
                  </Suspense>
                  {children}
                  <CommandPalette />
                  <Toaster />
                  <Suspense fallback={<FooterSkeleton />}>
                    <Footer />
                  </Suspense>
                </TimeContextProvider>
              </ServerBaseDataProvider>
            </Suspense>
          </RootLayoutClient>
          <GlobalErrorReporter />
        </AuthProvider>
      </body>
    </html>
  );
}

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

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Statbus",
  description: "Simple To Use, Simple To Understand, Simply useful!",
};

export default function RootLayout({
  children,
}: {
  readonly children: ReactNode;
}) {
  return (
    <html lang="en" className="h-full bg-white">
      <body
        className={cn(
          "grid h-full grid-rows-[auto_1fr_auto] font-sans antialiased",
          inter.className
        )}
      >
        <AuthProvider>
          <ServerBaseDataProvider>
            <Suspense fallback={<div>Loading...</div>}>
              <TimeContextProvider>
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
              </TimeContextProvider>
            </Suspense>
          </ServerBaseDataProvider>
          <GlobalErrorReporter />
        </AuthProvider>
      </body>
    </html>
  );
}

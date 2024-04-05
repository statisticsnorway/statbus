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
import TimeContextProvider from "@/app/time-context-provider";
import { SearchProvider } from "@/app/search/search-provider";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "StatBus",
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
        <TimeContextProvider>
          <Suspense fallback={<NavbarSkeleton />}>
            <Navbar />
          </Suspense>
          {children}
          <CommandPalette />
          <Toaster />
          <Suspense fallback={<FooterSkeleton />}>
            <Footer />
          </Suspense>
          <GlobalErrorReporter />
        </TimeContextProvider>
      </body>
    </html>
  );
}

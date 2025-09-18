"use client";
import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import Link from "next/link";
import { BarChartHorizontal, Search, Upload } from "lucide-react"; // Import Upload icon
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";
import { CommandPaletteTriggerMobileMenuButton } from "@/components/command-palette/command-palette-trigger-button";
import TimeContextSelector from "@/components/time-context-selector";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAuth, isAuthenticatedStrictAtom, currentUserAtom } from "@/atoms/auth";
import { useBaseData } from "@/atoms/base-data";
import { useWorkerStatus } from "@/atoms/worker_status";
import { useState } from "react";
import { usePathname } from "next/navigation"; // Import usePathname
import { useAtomValue } from "jotai";

export function NavbarSkeleton() {
  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Image src={logo} alt="Statbus Logo" className="h-10 w-10" />
      </div>
    </header>
  );
}

export default function Navbar() {
  const isAuthenticated = useAtomValue(isAuthenticatedStrictAtom); // Use derived atom
  const currentUser = useAtomValue(currentUserAtom); // Use derived atom
  const { hasStatisticalUnits } = useBaseData();
  const workerStatus = useWorkerStatus();
  const { isImporting, isDerivingUnits, isDerivingReports } = workerStatus;
  const pathname = usePathname(); // Get current pathname

  const [isClient, setIsClient] = useState(false);

  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'Navbar:setIsClient');

  // isAuthenticatedAtom is false if auth is loading, so !isAuthenticated covers both cases
  if (!isClient || !isAuthenticated) { 
    // If not client-side rendered yet, or if auth is loading or user is not authenticated,
    // show a simpler Navbar or skeleton.
    // For now, if not authenticated (which includes loading), we show a minimal navbar.
    // If truly not authenticated, many links won't be shown anyway.
    // If loading, this prevents showing links that depend on auth state prematurely.
    if (!isAuthenticated && isClient) { // Not authenticated (and not loading, or loading treated as not_auth)
      // Minimal navbar for non-authenticated users or during auth load
      return (
        <header className="bg-ssb-dark text-white">
          <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
            <Link
              href="/"
              className="flex items-center space-x-3 rtl:space-x-reverse"
            >
              <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
            </Link>
            {/* Placeholder for spacing if needed, or remove if logo should be left-aligned */}
            <div className="flex-1"></div> 
            <div className="flex items-center space-x-3">
              {/* No profile avatar or context selector if not authenticated */}
            </div>
          </div>
        </header>
      );
    }
    // If still SSR or initial client render before isAuth status is definitively known (and not false due to loading)
    // or if auth is loading (isAuthenticatedAtom will be false), show skeleton.
    // This condition simplifies to: if !isClient or (isClient && !isAuthenticated which implies loading or truly not auth)
    // The above block handles (isClient && !isAuthenticated). So this is for !isClient.
    if (!isClient) {
       return <NavbarSkeleton />;
    }
  }
  // At this point, isClient is true AND isAuthenticated is true (meaning not loading and authenticated)

  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto grid grid-cols-3 max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Link
          href="/"
          className="flex items-center space-x-3 rtl:space-x-reverse"
        >
          <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
        </Link>

        {/* Center: Main Navigation Links / Mobile Menu Trigger */}
        <div className="flex flex-1 justify-center space-x-3">
          {isAuthenticated && ( // isAuthenticated implies not loading and authenticated
            <>
              {/* Mobile Menu Trigger (Hamburger) */}
              <CommandPaletteTriggerMobileMenuButton className="lg:hidden" />

              {/* Import Link */}
              <Link
                href={isImporting ? "/import/jobs" : "/import"}
                className={cn(
                  buttonVariants({ variant: "ghost", size: "sm" }),
                  "space-x-2 hidden lg:flex",
                  // Add active state class
                  "border-1", // Base border class
                  isImporting
                    ? "border-yellow-400" // Processing state overrides active state
                    : pathname.startsWith("/import")
                      ? "border-white"
                      : "border-transparent" // Active/Inactive state
                )}
              >
                <Upload size={16} />
                <span>Import</span>
              </Link>
              {hasStatisticalUnits && (
                <>
                  {/* Search Link */}
                  <Link
                    href="/search"
                    className={cn(
                      buttonVariants({ variant: "ghost", size: "sm" }),
                      "space-x-2 hidden lg:flex",
                      // Add active state class
                      "border-1", // Base border class
                      isDerivingUnits
                        ? "border-yellow-400" // Processing state overrides active state
                        : pathname.startsWith("/search")
                          ? "border-white"
                          : "border-transparent" // Active/Inactive state
                    )}
                  >
                    <Search size={16} />
                    <span>Statistical Units</span>
                  </Link>
                  {/* Reports Link */}
                  <Link
                    href="/reports"
                    className={cn(
                      buttonVariants({ variant: "ghost", size: "sm" }),
                      "space-x-2 hidden lg:flex",
                      // Add active state class
                      "border-1", // Base border class
                      isDerivingReports
                        ? "border-yellow-400" // Processing state overrides active state
                        : pathname.startsWith("/reports")
                          ? "border-white"
                          : "border-transparent" // Active/Inactive state
                    )}
                  >
                    <BarChartHorizontal size={16} />
                    <span>Reports</span>
                  </Link>
                </>
              )}
            </>
          )}
        </div>

        {/* Right: Context/Profile/Mobile */}
        <div className="flex items-center justify-end space-x-3">
          {isAuthenticated &&
            hasStatisticalUnits && ( // isAuthenticated implies not loading and authenticated
              <TimeContextSelector />
            )}
          {/* Render ProfileAvatar only if authenticated and user object is available */}
          {isAuthenticated &&
            currentUser && ( // isAuthenticated implies not loading and authenticated
              <>
                <ProfileAvatar className="w-8 h-8 text-ssb-dark hidden lg:flex" />
                {/* Mobile menu button moved to the center section */}
              </>
            )}
        </div>
      </div>
    </header>
  );
}

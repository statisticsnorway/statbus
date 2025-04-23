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
import { useAuth } from "@/hooks/useAuth";
import { useBaseData } from "@/app/BaseDataClient";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation"; // Import usePathname

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
  const { isAuthenticated } = useAuth();
  const { hasStatisticalUnits } = useBaseData();
  const pathname = usePathname(); // Get current pathname

  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  if (!isClient) {
    return <NavbarSkeleton />;
  }

  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Link
          href="/"
          className="flex items-center space-x-3 rtl:space-x-reverse"
        >
          <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
        </Link>

        {/* Center: Main Navigation Links */}
        <div className="flex flex-1 justify-center space-x-3">
          {isAuthenticated && hasStatisticalUnits && (
            <>
              {/* Import Link */}
              <Link
                href="/import"
                className={cn(
                  buttonVariants({ variant: "ghost", size: "sm" }),
                  "space-x-2 hidden lg:flex",
                  // Add active state class
                  pathname.startsWith("/import") && "border-1 border-white" 
                )}
              >
                <Upload size={16} />
                <span>Import</span>
              </Link>
              {/* Search Link */}
              <Link
                href="/search"
                className={cn(
                  buttonVariants({ variant: "ghost", size: "sm" }),
                  "space-x-2 hidden lg:flex",
                  // Add active state class
                  pathname.startsWith("/search") && "border-1 border-white"
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
                  pathname.startsWith("/reports") && "border-1 border-white"
                )}
              >
                <BarChartHorizontal size={16} />
                <span>Reports</span>
              </Link>
            </>
          )}
        </div>

        {/* Right: Context/Profile/Mobile */}
        <div className="flex items-center space-x-3">
          {isAuthenticated && hasStatisticalUnits && (
            <TimeContextSelector />
          )}
          {isAuthenticated && (
            <>
              <ProfileAvatar className="w-8 h-8 text-ssb-dark hidden lg:flex" />
              <CommandPaletteTriggerMobileMenuButton className="lg:hidden" />
            </>
          )}
        </div>
      </div>
    </header>
  );
}

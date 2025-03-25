"use client";
import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import Link from "next/link";
import { BarChartHorizontal, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";
import { CommandPaletteTriggerMobileMenuButton } from "@/components/command-palette/command-palette-trigger-button";
import TimeContextSelector from "@/components/time-context-selector";

export function NavbarSkeleton() {
  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Image src={logo} alt="Statbus Logo" className="h-10 w-10" />
      </div>
    </header>
  );
}

import { useAuth } from "@/hooks/useAuth";
import { useBaseData } from "@/app/BaseDataClient";

export default function Navbar() {
  const { isAuthenticated } = useAuth();
  const { hasStatisticalUnits } = useBaseData();

  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Link
          href="/"
          className="flex items-center space-x-3 rtl:space-x-reverse"
        >
          <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
        </Link>
        <div className="flex-1 space-x-3 flex items-center justify-end">
          {isAuthenticated && hasStatisticalUnits && (
            <>
              <TimeContextSelector />
              <Link
                href="/reports"
                className={cn(
                  buttonVariants({ variant: "ghost", size: "sm" }),
                  "space-x-2 hidden lg:flex"
                )}
              >
                <BarChartHorizontal size={16} />
                <span>Reports</span>
              </Link>
              <Link
                href="/search"
                className={cn(
                  buttonVariants({ variant: "ghost", size: "sm" }),
                  "space-x-2 hidden lg:flex"
                )}
              >
                <Search size={16} />
                <span>Statistical Units</span>
              </Link>
            </>
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

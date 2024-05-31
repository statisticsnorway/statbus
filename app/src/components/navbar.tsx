import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import Link from "next/link";
import { BarChartHorizontal, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";
import { CommandPaletteTriggerMobileMenuButton } from "@/components/command-palette/command-palette-trigger-button";
import TimeContextSelector from "@/components/time-context-selector";
import { createClient } from "@/lib/supabase/server";

export function NavbarSkeleton() {
  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-screen-xl items-center justify-between gap-4 p-2 lg:px-4">
        <Image src={logo} alt="Statbus Logo" className="h-10 w-10" />
      </div>
    </header>
  );
}

export default async function Navbar() {
  const supabase = createClient();
  const session = await supabase.auth.getSession();
  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-screen-xl items-center justify-between gap-4 p-2 lg:px-4">
        <a href="/" className="flex items-center space-x-3 rtl:space-x-reverse">
          <Image src={logo} alt="Statbus Logo" className="h-10 w-10" />
        </a>
        {session.data.session?.user && (
          <div className="flex-1 space-x-3 flex items-center justify-end">
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
            <ProfileAvatar className="w-8 h-8 text-ssb-dark hidden lg:flex" />
            <CommandPaletteTriggerMobileMenuButton className="lg:hidden" />
          </div>
        )}
      </div>
    </header>
  );
}

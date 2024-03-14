import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import Link from "next/link";
import { BarChartHorizontal, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";

export default function Navbar() {
  return (
    <header>
      <div className="mx-auto flex max-w-screen-xl items-center justify-between gap-4 p-4 border-b-2 border-ssb-dark">
        <a href="/" className="flex items-center space-x-3 rtl:space-x-reverse">
          <Image
            src={logo}
            alt="StatBus Logo"
            width={32}
            height={32}
            className="h-8"
          />
        </a>
        <div className="flex flex-1 items-center justify-end gap-8">
          <div className="hidden space-x-3 lg:flex">
            <Link
              href="/reports"
              className={cn(
                buttonVariants({ variant: "ghost", size: "sm" }),
                "space-x-2"
              )}
            >
              <BarChartHorizontal size={16} />
              <span>Reports</span>
            </Link>
            <Link
              href="/search"
              className={cn(
                buttonVariants({ variant: "ghost", size: "sm" }),
                "space-x-2"
              )}
            >
              <Search size={16} />
              <span>Statistical Units</span>
            </Link>
          </div>
          <div
            className="order-1 flex w-auto items-center justify-between"
            id="navbar-user"
          >
            <ul className="flex flex-col font-medium">
              <li>
                <ProfileAvatar />
              </li>
            </ul>
          </div>
        </div>
      </div>
    </header>
  );
}

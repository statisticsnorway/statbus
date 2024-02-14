import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from '@/../public/statbus-logo.png'
import Link from "next/link";
import {ScrollText, Search} from "lucide-react";
import {cn} from "@/lib/utils";
import {buttonVariants} from "@/components/ui/button";

export default function Navbar() {
  return (
    <nav className="bg-gray-50 border-b-2 border-gray-100">
      <div className="max-w-screen-xl flex items-center justify-between mx-auto p-4 gap-4">
        <a href="/" className="flex items-center space-x-3 rtl:space-x-reverse">
          <Image src={logo} alt="StatBus Logo" width={32} height={32} className="h-8"/>
          <span className="self-center text-2xl font-semibold whitespace-nowrap dark:text-white">StatBus</span>
        </a>
        <div className="flex-1 flex items-center gap-8 justify-end">
          <div className="space-x-3">
            <Link
              href="/reports"
              className={cn(buttonVariants({variant: "outline", size: "sm"}), "font-normal space-x-2")}
            >
              <ScrollText size={16}/>
              <span>Reports</span>
            </Link>
            <Link
              href="/search"
              className={cn(buttonVariants({variant: "outline", size: "sm"}), "font-normal space-x-2")}
            >
              <Search size={16}/>
              <span>Statistical Units</span>
            </Link>
          </div>
          <div className="items-center justify-between flex w-auto order-1" id="navbar-user">
            <ul className="flex flex-col font-medium">
              <li>
                <ProfileAvatar/>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </nav>
  )
}

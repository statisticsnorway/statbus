import CommandPaletteTriggerButton from "@/components/command-palette/command-palette-trigger-button";
import { Separator } from "@/components/ui/separator";
import Link from "next/link";
import { Github, Globe } from "lucide-react";
import logo from "@/../public/ssb_logo_white.svg";
import Image from "next/image";

export default function Footer() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-screen-xl space-y-10 p-6 lg:p-24">
        <div className="flex items-center justify-between space-x-2">
          <Image src={logo} alt="SSB Logo" className="h-8 lg:h-12 w-auto" />
          <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
        </div>
        <Separator className="bg-gray-200" />
        <div className="flex justify-between text-gray-500">
          <span></span>
          <div className="flex items-center justify-between space-x-3">
            <Link href="https://github.com/statisticsnorway/statbus/">
              <Github size={22} className="stroke-ssb-neon" />
            </Link>
            <Link href="https://www.statbus.org">
              <Globe size={22} className="stroke-ssb-neon" />
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}

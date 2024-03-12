import CommandPaletteTriggerButton from "@/components/command-palette/command-palette-trigger-button";
import { Separator } from "@/components/ui/separator";
import Link from "next/link";
import { Github, Globe } from "lucide-react";

export default function Footer() {
  return (
    <footer className="border-t-2 border-gray-100 bg-gray-50">
      <div className="mx-auto max-w-screen-xl space-y-8 p-6 lg:p-12">
        <div className="flex items-center justify-between space-x-2">
          <span></span>
          <CommandPaletteTriggerButton className="text-gray-500 max-lg:hidden" />
        </div>
        <Separator className="bg-gray-200" />
        <div className="flex justify-between text-gray-500">
          <span className="text-sm">By Statistics Norway | 2024</span>
          <div className="flex items-center justify-between space-x-3">
            <Link href="https://github.com/statisticsnorway/statbus/">
              <Github size={18} />
            </Link>
            <Link href="https://www.statbus.org">
              <Globe size={18} />
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}

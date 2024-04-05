import CommandPaletteTriggerButton from "@/components/command-palette/command-palette-trigger-button";
import { Separator } from "@/components/ui/separator";
import Link from "next/link";
import { Github, Globe } from "lucide-react";
import { SSBLogo } from "@/components/ssb-logo";
import { createClient } from "@/lib/supabase/server";

export function FooterSkeleton() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-screen-xl space-y-10 p-6 lg:p-24">
        <div className="flex items-center justify-between space-x-2">
          <SSBLogo className="h-8 lg:h-12 w-auto" />
        </div>
      </div>
    </footer>
  );
}

export default async function Footer() {
  const supabase = createClient();
  const session = await supabase.auth.getSession();

  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-screen-xl space-y-12 p-6 lg:p-24">
        <div className="flex items-center justify-between space-x-2">
          <SSBLogo className="h-8 lg:h-12 w-auto" />
          {session.data.session?.user && (
            <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
          )}
        </div>
        <Separator className="bg-gray-200" />
        <div className="flex justify-between text-gray-500">
          <span></span>
          <div className="flex items-center justify-between space-x-3">
            <Link
              href="https://github.com/statisticsnorway/statbus/"
              aria-label="Github Repository"
            >
              <Github size={22} className="stroke-ssb-neon" />
            </Link>
            <Link href="https://www.statbus.org" aria-label="SSB homepage">
              <Globe size={22} className="stroke-ssb-neon" />
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}

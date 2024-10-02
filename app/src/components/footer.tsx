import { createClient } from "@/utils/supabase/server";
import Link from "next/link";
import { Github, Globe } from "lucide-react";
import { SSBLogo } from "@/components/ssb-logo";
import { Session } from "@supabase/auth-js/src/lib/types"
import { CommandPaletteTriggerButton } from "@/components/command-palette/command-palette-trigger-button";

export function FooterSkeleton() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-screen-xl p-6 lg:py-12 lg:px-24">
        <div className="flex items-center justify-between space-x-2">
          <SSBLogo className="h-8 lg:h-12 w-auto" />
        </div>
      </div>
    </footer>
  );
}

export default async function Footer() {
  const {client} = createClient();
  const { data: { session } } = await client.auth.getSession();

  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-screen-xl p-6 lg:py-12 lg:px-24">
        <div className="flex items-center justify-between space-x-2">
          <SSBLogo className="h-8 lg:h-12 w-auto" />

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
          {session?.user && (
            <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
          )}
        </div>
      </div>
    </footer>
  );
}

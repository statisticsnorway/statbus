import { getServerRestClient } from "@/context/RestClientStore";
import Link from "next/link";
import { Github, Globe } from "lucide-react";
import { CommandPaletteTriggerButton } from "@/components/command-palette/command-palette-trigger-button";

export function FooterSkeleton() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div className="flex items-center justify-between space-x-2"></div>
      </div>
    </footer>
  );
}

export default async function Footer() {
  // Check if user is authenticated using AuthStore
  const { authStore } = await import('@/context/AuthStore');
  const authStatus = await authStore.getAuthStatus();
  const isAuthenticated = authStatus.isAuthenticated;

  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div
          className={`flex items-center space-x-2 ${
            isAuthenticated ? "justify-between" : "justify-center"
          }`}
        >
          <div className="flex items-center justify-between space-x-3">
            <Link
              href="https://github.com/statisticsnorway/statbus/"
              aria-label="Github Repository"
            >
              <Github size={22} className="stroke-ssb-neon" />
            </Link>
            <Link href="https://www.statbus.org" aria-label="Statbus homepage">
              <Globe size={22} className="stroke-ssb-neon" />
            </Link>
          </div>
          {isAuthenticated && (
            <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
          )}
        </div>
      </div>
    </footer>
  );
}

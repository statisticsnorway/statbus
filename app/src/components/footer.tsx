"use client";

import Link from "next/link";
import { Github, Globe } from "lucide-react";
import { CommandPaletteTriggerButton } from "@/components/command-palette/command-palette-trigger-button";
import { useAuth } from "@/atoms/hooks";

export function FooterSkeleton() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div className="flex items-center justify-between space-x-2"></div>
      </div>
    </footer>
  );
}

import { useEffect, useState } from "react";

export default function Footer() {
  const [mounted, setMounted] = useState(false);
  // Use Jotai hook to get authentication status
  const { isAuthenticated } = useAuth();

  useEffect(() => {
    setMounted(true);
  }, []);

  // Determine justification based on mounted state and authentication
  // Default to 'justify-center' for SSR and initial client render
  const justificationClass = mounted && isAuthenticated ? "justify-between" : "justify-center";

  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div
          className={`flex items-center space-x-2 ${justificationClass}`}
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
          {/* Only render CommandPaletteTriggerButton if mounted and authenticated */}
          {mounted && isAuthenticated && (
            <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
          )}
        </div>
      </div>
    </footer>
  );
}

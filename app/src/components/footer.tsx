"use client";

import Link from "next/link";
import { Github, Globe } from "lucide-react";
import { CommandPaletteTriggerButton } from "@/components/command-palette/command-palette-trigger-button";
import { useAtomValue, useSetAtom } from "jotai";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { isAuthenticatedStrictAtom } from "@/atoms/auth";
import { statbusConfig } from "@/lib/statbus-config";
import {
  refreshRunningIdentityAtom,
  runningIdentityAtom,
} from "@/atoms/running-identity";
import { runningVersionDisplay } from "@/lib/running-identity";

export function FooterSkeleton() {
  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div className="flex items-center justify-between space-x-2"></div>
      </div>
    </footer>
  );
}

import { useState } from "react";

export default function Footer() {
  const [mounted, setMounted] = useState(false);
  // Use derived isAuthenticatedAtom which handles loading state internally
  const isAuthenticated = useAtomValue(isAuthenticatedStrictAtom);
  const runningIdentity = useAtomValue(runningIdentityAtom);
  const refreshRunningIdentity = useSetAtom(refreshRunningIdentityAtom);

  useGuardedEffect(
    () => {
      setMounted(true);
    },
    [],
    "Footer:setMounted"
  );

  useGuardedEffect(
    () => {
      void refreshRunningIdentity();
      const refreshInterval = window.setInterval(() => {
        void refreshRunningIdentity();
      }, 30000);
      return () => window.clearInterval(refreshInterval);
    },
    [refreshRunningIdentity],
    "Footer:refreshRunningIdentity"
  );

  // Determine justification based on mounted state and authentication
  // isAuthenticated is false if loading or not authenticated
  const showAuthenticatedLayout = mounted && isAuthenticated;
  const justificationClass = showAuthenticatedLayout
    ? "justify-between"
    : "justify-center";
  const version = runningVersionDisplay(
    runningIdentity,
    statbusConfig.fallbackVersion,
    statbusConfig.fallbackCommit
  );
  const versionHref =
    runningIdentity?.release_status === "commit"
      ? `https://github.com/statisticsnorway/statbus/commit/${runningIdentity.commit_sha}`
      : `https://github.com/statisticsnorway/statbus/releases/tag/${version.name}`;
  const buildDetails =
    runningIdentity?.build_name &&
    runningIdentity.build_name !== runningIdentity.resolved_name
      ? `Built as ${runningIdentity.build_name}`
      : undefined;

  return (
    <footer className="border-t-2 border-gray-100 bg-ssb-dark">
      <div className="mx-auto max-w-(--breakpoint-xl) p-6 lg:py-12 lg:px-24">
        <div className={`flex items-center space-x-2 ${justificationClass}`}>
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
            <span className="text-xs text-gray-300" title={buildDetails}>
              Statbus version{" "}
              <Link
                href={versionHref}
                className="hover:text-ssb-neon underline"
              >
                {version.name}
              </Link>
              {version.commit && (
                <>
                  {" ("}
                  <Link
                    href={`https://github.com/statisticsnorway/statbus/commit/${runningIdentity?.commit_sha ?? version.commit}`}
                    className="hover:text-ssb-neon underline"
                  >
                    {version.commit}
                  </Link>
                  {")"}
                </>
              )}
            </span>
          </div>
          {/* Only render CommandPaletteTriggerButton if mounted, not loading, and authenticated */}
          {showAuthenticatedLayout && (
            <CommandPaletteTriggerButton className="text-white bg-transparent max-lg:hidden" />
          )}
        </div>
      </div>
    </footer>
  );
}

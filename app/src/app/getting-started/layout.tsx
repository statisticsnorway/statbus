"use client";

import React from "react";
import Link from "next/link";
import { useAtomValue } from "jotai";
import { Loader2 } from "lucide-react";
import { usePermission } from "@/atoms/auth";
import { useAppReady, setupRedirectCheckAtom } from "@/atoms/app-derived";

export default function GettingStartedLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  const { isAuthProcessComplete } = useAppReady();
  const { canAccessGettingStarted } = usePermission();
  const setupCheck = useAtomValue(setupRedirectCheckAtom);

  if (isAuthProcessComplete && canAccessGettingStarted) {
    return (
      <main className="w-full mx-auto max-w-(--breakpoint-xl) px-2 py-8 md:py-12 grid lg:grid-cols-12 gap-8">
        <aside className="p-6 pb-12 col-span-12 lg:col-span-4 bg-ssb-light">
          {progress}
        </aside>
        <div className="flex-1 col-span-12 lg:col-span-8 py-6">
          <div className="max-w-2xl mx-auto">{children}</div>
        </div>
      </main>
    );
  }

  if (!isAuthProcessComplete || setupCheck.isLoading) {
    return (
      <div className="flex justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin" />
      </div>
    );
  }

  const isSetupPending = setupCheck.path?.startsWith("/getting-started");

  return (
    <main className="w-full mx-auto max-w-2xl px-2 py-24 space-y-4 text-center">
      {isSetupPending ? (
        <>
          <h1 className="text-2xl">Statbus is not set up yet</h1>
          <p>
            This installation has not been set up. An administrator has to
            complete the Getting Started guide before Statbus can be used.
          </p>
        </>
      ) : (
        <>
          <h1 className="text-2xl">No access</h1>
          <p>
            You don’t have access to the Getting Started guide. Only
            administrators can change the setup.
          </p>
          <Link href="/" className="inline-block underline">
            Return to Home
          </Link>
        </>
      )}
    </main>
  );
}

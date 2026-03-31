"use client";

import { useAtomValue } from "jotai";
import { pendingUpgradeStatusAtom } from "@/atoms/upgrade-status";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { usePathname } from "next/navigation";

/**
 * Redirects ALL users to the maintenance page when an upgrade is in progress.
 *
 * Mounted in the root layout. When the upgrade service starts an upgrade,
 * the status changes to "in_progress" and this component redirects to
 * /maintenance.html with a return URL. The maintenance page shows live
 * progress and auto-redirects back when the app is healthy.
 *
 * Skips redirect if already on the maintenance page or the upgrades admin page
 * (which has its own maintenance view).
 */
export function UpgradeMaintenanceGuard() {
  const upgradeStatus = useAtomValue(pendingUpgradeStatusAtom);
  const pathname = usePathname();

  useGuardedEffect(() => {
    if (
      upgradeStatus === "in_progress" &&
      typeof window !== "undefined" &&
      !pathname?.startsWith("/admin/upgrades")
    ) {
      const returnPath = encodeURIComponent(window.location.pathname);
      window.location.href = `/maintenance.html?return=${returnPath}`;
    }
  }, [upgradeStatus, pathname], 'UpgradeMaintenanceGuard:redirect');

  return null;
}

"use client"; // Make it a client component

// import { getServerRestClient } from "@/context/RestClientStore"; // No longer needed
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { ScrollText } from "lucide-react";
import { useAtomValue } from 'jotai';
import { settingsAtomAsync } from "@/atoms/getting-started";

export const ActivityCategoryCard = () => {
  const setting = useAtomValue(settingsAtomAsync);
  // The atom returns null if not found or on error.
  // We consider it "not set" if null, rather than a hard "failed" state for the card display.
  // Actual fetch errors are logged by the atom itself.
  const isNotSet = setting === null;

  return (
    <DashboardCard
      title="Activity Category Standard"
      icon={<ScrollText className="h-4" />}
      text={
        setting?.activity_category_standard?.name ??
        (isNotSet ? "Not Set" : "-")
      } // Show "Not Set" if null
      failed={false} // Avoid showing error style just because it's not set.
                     // True failure (e.g. API down) would be handled by Suspense error boundary or atom's internal logging.
    />
  );
};

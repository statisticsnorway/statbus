"use client"; 

import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Globe2 } from "lucide-react";
import { useAtomValue } from 'jotai';
import { numberOfRegionsAtomAsync } from '@/atoms/getting-started';

export const RegionCard = () => {
  const count = useAtomValue(numberOfRegionsAtomAsync);
  // The atom returns null if not authenticated, if client is null, or on fetch error.
  const failed = count === null; 

  return (
    <DashboardCard
      title="Region Hierarchy"
      icon={<Globe2 className="h-4" />}
      text={count?.toString() ?? (failed ? "Error" : "-")}
      failed={failed}
    />
  );
};

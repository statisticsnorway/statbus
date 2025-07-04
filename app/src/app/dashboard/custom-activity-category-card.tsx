"use client"; // Make it a client component

// import { getServerRestClient } from "@/context/RestClientStore"; // No longer needed
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { Settings } from "lucide-react";
import { useAtomValue } from 'jotai';
import { numberOfCustomActivityCodesAtomAsync } from '@/atoms/getting-started';

export const CustomActivityCategoryCard = () => {
  const count = useAtomValue(numberOfCustomActivityCodesAtomAsync);
  const failed = count === null;

  return (
    <DashboardCard
      title="Custom Activity Category Codes"
      icon={<Settings className="h-4" />}
      text={count?.toString() ?? (failed ? "Error" : "-")}
      failed={failed}
    />
  );
};

"use client"; // Make it a client component

// import { getServerRestClient } from "@/context/RestClientStore"; // No longer needed
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { BookText } from "lucide-react";
import { useAtomValue } from 'jotai';
import { numberOfTotalActivityCodesAtomAsync } from '@/atoms/getting-started';

export const TotalActivityCategoryCard = () => {
  const count = useAtomValue(numberOfTotalActivityCodesAtomAsync);
  const failed = count === null;

  return (
    <DashboardCard
      title="All Activity Category Codes"
      icon={<BookText className="h-4" />}
      text={count?.toString() ?? (failed ? "Error" : "-")}
      failed={failed}
    />
  );
};

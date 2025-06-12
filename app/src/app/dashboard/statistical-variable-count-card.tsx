"use client"; // Make it a client component

// import { getServerRestClient } from "@/context/RestClientStore"; // No longer needed
import { DashboardCard } from "@/app/dashboard/dashboard-card";
import { BarChart3 } from "lucide-react";
// import { Suspense } from "react"; // Suspense will be handled by the parent
// import { FallBackCard } from "./fallBack-card"; // Fallback handled by parent
import { useAtomValue } from 'jotai';
import { statDefinitionsAtom } from '@/atoms'; // Assuming statDefinitionsAtom holds the active ones or we need a new atom

export const StatisticalVariableCountCard = () => {
  // This atom currently holds all stat_definition_active from baseDataAtom.
  // If you need a specific atom that just fetches the count, it should be created.
  // For now, we derive the count from the length of the statDefinitions array.
  const statDefinitions = useAtomValue(statDefinitionsAtom);
  const count = statDefinitions?.length; // The atom resolves to the array or empty array
  const failed = statDefinitions === null; // If baseDataAtom itself failed to load this part.

  return (
    <DashboardCard
      title="Statistical Variables"
      icon={<BarChart3 className="h-4" />}
      text={count?.toString() ?? (failed ? "Error" : "-")}
      failed={failed}
    />
  );
};

"use client";
import { DrillDown, DrillDownPoint } from "@/app/reports/types/drill-down";
import { useState } from "react";
import { useTimeContext } from '@/atoms/app-derived';
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

export const useDrillDownData = () => {
  const { selectedTimeContext } = useTimeContext();
  const [region, setRegion] = useState<DrillDownPoint | null>(null);
  const [activityCategory, setActivityCategory] =
    useState<DrillDownPoint | null>(null);

  const urlSearchParams = new URLSearchParams();

  if (region?.path) {
    urlSearchParams.set("region_path", region?.path);
  }

  if (activityCategory?.path) {
    urlSearchParams.set("activity_category_path", activityCategory?.path);
  }

  if (selectedTimeContext?.valid_on) {
    urlSearchParams.set("valid_on", selectedTimeContext.valid_on);
  }

  // SWR handles caching internally - no need for a separate Map cache
  const fetcher = async (url: string) => {
    const response = await fetchWithAuthRefresh(url);
    
    // Check for JWT expiration in the response
    if (response.status === 401) {
      const text = await response.text();
      if (text.includes("JWT expired") || text.includes("PGRST301")) {
        throw new JwtExpiredError();
      }
      throw new Error(`Unauthorized: ${text}`);
    }
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    return response.json();
  };

  const swrResponse = useSWRWithAuthRefresh<DrillDown>(
    `/api/reports?${urlSearchParams.toString()}`,
    fetcher,
    {
      keepPreviousData: true,
      revalidateOnFocus: false, // Don't refetch when user returns to the tab
    },
    "useDrillDownData"
  );

  // Use initial data when no parameters are present
  const drillDown = swrResponse.data;

  return {
    drillDown,
    region,
    setRegion,
    activityCategory,
    setActivityCategory,
  };
};

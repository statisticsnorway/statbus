"use client";
import { Enums } from "@/lib/database.types";
import { fetchWithAuthRefresh } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

export const useStatisticalHistoryChanges = (
  unitType: UnitType,
  resolution: Enums<"history_resolution"> = "year",
  series_codes: string[],
  year?: number
) => {
  const urlSearchParams = new URLSearchParams();

  urlSearchParams.set("resolution", resolution);
  urlSearchParams.set("unit_type", unitType);
  urlSearchParams.set("series_codes", series_codes.join(","));
  if (year) {
    urlSearchParams.set("year", year.toString());
  }

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

  const { data: history, isLoading } = useSWRWithAuthRefresh<StatisticalHistoryHighcharts>(
    `/api/reports/history-changes?${urlSearchParams.toString()}`,
    fetcher,
    {
      keepPreviousData: true,
    },
    "useStatisticalHistoryChanges"
  );

  return {
    history,
    isLoading,
  };
};

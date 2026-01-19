"use client";
import useSWR from "swr";
import { Enums } from "@/lib/database.types";
import { fetchWithAuthRefresh } from "@/context/RestClientStore";

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

  const fetcher = (url: string) =>
    fetchWithAuthRefresh(url).then((res) => res.json());

  const { data: history, isLoading } = useSWR<StatisticalHistoryHighcharts>(
    `/api/reports/history-changes?${urlSearchParams.toString()}`,
    fetcher,
    {
      keepPreviousData: true,
    }
  );

  return {
    history,
    isLoading,
  };
};

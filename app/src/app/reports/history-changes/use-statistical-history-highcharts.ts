"use client";
import { Enums } from "@/lib/database.types";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh } from "@/hooks/use-swr-with-auth-refresh";

export const useStatisticalHistoryHighcharts = (
  resolution: Enums<"history_resolution"> = "year",
  unitType: UnitType,
  series_codes: string[],
  year?: number
) => {
  const swrKey = [
    "statistical_history_highcharts",
    resolution,
    unitType,
    series_codes.join(","),
    year ?? "",
  ];

  const fetcher = async (): Promise<any> => {
    const client = await getBrowserRestClient();
    const { data, error } = await client.rpc("statistical_history_highcharts", {
      p_resolution: resolution,
      p_unit_type: unitType,
      p_series_codes: series_codes,
      p_year: year,
    });

    if (error) throw new Error(error.message);
    return data;
  };

  const { data: history, isLoading } =
    useSWRWithAuthRefresh<StatisticalHistoryHighcharts>(
      swrKey,
      fetcher,
      { keepPreviousData: true },
      "useStatisticalHistoryHighcharts"
    );

  return { history, isLoading };
};

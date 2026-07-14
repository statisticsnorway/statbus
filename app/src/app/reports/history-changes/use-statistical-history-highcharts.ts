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

  const fetcher = async () => {
    const client = await getBrowserRestClient();
    const { data, error } = await client.rpc("statistical_history_highcharts", {
      p_resolution: resolution,
      p_unit_type: unitType,
      p_series_codes: series_codes,
      p_year: year,
    });

    if (error) {
      // PostgREST exposes RAISE HINT as `error.hint`. The Postgres function
      // statistical_history_highcharts emits structured completion suggestions
      // there (e.g. "Try one of: stats_summary.turnover.sum, ...") — surface
      // them alongside the message so the user sees the actual guidance, not
      // just the failure summary.
      throw new Error([error.message, error.hint].filter(Boolean).join("\n"));
    }
    // PostgREST types the RPC result as generic Json; the function contract
    // guarantees the StatisticalHistoryHighcharts shape (external-boundary cast).
    return data as unknown as StatisticalHistoryHighcharts;
  };

  const {
    data: history,
    isLoading,
    error,
  } = useSWRWithAuthRefresh<StatisticalHistoryHighcharts>(
    swrKey,
    fetcher,
    { keepPreviousData: true },
    "useStatisticalHistoryHighcharts"
  );

  return { history, isLoading, error };
};

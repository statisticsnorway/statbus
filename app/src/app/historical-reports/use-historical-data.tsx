import { useState } from "react";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<any[], string> = (...args) =>
  fetch(...args).then((res) => res.json());

export default function useHistoricalData() {
  const [year, setYear] = useState<string | null>(null);
  const [unitType, setUnitType] = useState<string | null>("enterprise");
  const [type, setType] = useState<string | null>("year");
  const searchParams = new URLSearchParams();

  if (year) {
    searchParams.set("year", year);
  }

  if (unitType) {
    searchParams.set("unit_type", unitType);
  }

  if (type) {
    searchParams.set("type", type);
  }

  const { data } = useSWR<any[]>(
    `/api/historical-reports?${searchParams}`,
    fetcher
  );

  return { data, year, setYear, unitType, setUnitType, type, setType };
}

import useSWR from "swr";
export default function useHierarchyStats(
  unitId: number,
  unitType: UnitType,
  compact: boolean
) {
  const urlSearchParams = new URLSearchParams();

  urlSearchParams.set("unitId", unitId.toString());
  urlSearchParams.set("unitType", unitType);

  const fetcher = async (url: string) => {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error("Failed to fetch statistical unit stats");
    }
    return response.json();
  };

  const { data } = useSWR<StatisticalUnitStats[]>(
    () => (!compact ? `/api/hierarchy-stats?${urlSearchParams}` : null),
    fetcher,
    {
      keepPreviousData: true,
      revalidateOnFocus: false,
    }
  );

  return {
    hierarchyStats: data,
  };
}

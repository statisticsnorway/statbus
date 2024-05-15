type RegionResult = {
  regions: Tables<"region">[];
  count: number;
};
interface RegionTableProps {
  regions: Tables<"region">[];
}
interface RegionTableRowProps {
  region: Tables<"region">;
}

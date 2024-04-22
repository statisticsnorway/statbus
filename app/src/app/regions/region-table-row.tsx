import { TableCell, TableRow } from "@/components/ui/table";
import { Tables } from "@/lib/database.types";

export default function RegionTableRow({
  region,
}: {
  region: Tables<"region">;
}) {
  const { code, name } = region;

  return (
    <TableRow>
      <TableCell className="py-2">{code}</TableCell>
      <TableCell className="py-2">{name}</TableCell>
    </TableRow>
  );
}

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function UnitHistoryTable({
  unitHistory,
}: {
  readonly unitHistory: UnitHistory[] | null;
}) {
  if (!unitHistory) return;
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Valid from</TableHead>
          <TableHead>Name</TableHead>
          <TableHead>Primary Activity</TableHead>
          <TableHead>Region</TableHead>
          <TableHead>Status</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {unitHistory &&
          unitHistory.map((unit) => (
            <TableRow key={unit.valid_from}>
              <TableCell>{unit.valid_from}</TableCell>
              <TableCell>{unit.name}</TableCell>
              <TableCell>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{unit.primary_activity_category?.code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-36">
                    {unit.primary_activity_category?.name}
                  </small>
                </div>
              </TableCell>
              <TableCell>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{unit.physical_region?.code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-36">
                    {unit.physical_region?.name}
                  </small>
                </div>
              </TableCell>
              <TableCell>{unit?.status?.name}</TableCell>
            </TableRow>
          ))}
      </TableBody>
    </Table>
  );
}

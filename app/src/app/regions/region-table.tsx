import React from "react";
import {
  Table,
  TableBody,
  TableHeader,
  TableRow,
  TableCell,
} from "@/components/ui/table";
const RegionTable = ({ regions }: RegionTableProps) => {
  return (
    <Table className="font-sans">
      <TableHeader className="bg-gray-50">
        <TableRow>
          <TableCell>Code</TableCell>
          <TableCell>Path</TableCell>
          <TableCell>Name</TableCell>
        </TableRow>
      </TableHeader>
      <TableBody>
        {regions.map(({ id, code, path, name }) => (
          <TableRow key={id}>
            <TableCell className="py-3">{code}</TableCell>
            <TableCell className="py-3">{path}</TableCell>
            <TableCell className="py-3 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-72">
              {name}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
};
export default RegionTable;

import React from "react";
import {
  Table,
  TableBody,
  TableHeader,
  TableRow,
  TableCell,
  TableHead,
} from "@/components/ui/table";

import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";

export interface ColumnDefinition<T> {
  key: keyof T;
  header: string;
  render?: ((item: T) => React.ReactNode);
  className?: string;
}

interface AdminTableProps<T extends { id: any }> {
  readonly data: T[];
  readonly columns: ColumnDefinition<T>[];
  readonly onEdit: (item: T) => void;
  readonly isLoading?: boolean;
}

export default function AdminTable<T extends { id: any }>({
  data,
  columns,
  onEdit,
  isLoading = false,
}: AdminTableProps<T>) {
  return (
    <>
      {isLoading ? (
        <Skeleton className="h-[240px] w-full" />
      ) : (
        <Table className="bg-white">
          <TableHeader className="bg-gray-50">
            <TableRow>
              {columns.map((col) => (
                <TableHead key={col.header}>{col.header}</TableHead>
              ))}
              <TableHead></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((record) => (
              <TableRow key={record.id}>
                {columns.map((col) => (
                  <TableCell
                    key={String(col.key)}
                    className={`py-3 ${col.className ?? ""}`}
                  >
                    {col.render ? col.render(record) : String(record[col.key])}
                  </TableCell>
                ))}
                <TableCell className="text-right">
                  <Button
                    variant="ghost"
                    className="inline-block"
                    onClick={() => onEdit(record)}
                  >
                    <Pencil className="w-4 h-4" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}

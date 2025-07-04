"use client";

import { useTableColumnsManager as useTableColumns } from '@/atoms/search';
import { TableColumn } from "../search.d";

interface FilterWrapperProps {
  columnCode: TableColumn["code"];
  statCode?: string | null;
  children: React.ReactNode;
}

export function FilterWrapper({ columnCode, statCode = null, children }: FilterWrapperProps) {
  const { visibleColumns } = useTableColumns();

  // Check if this column is visible
  const isVisible = visibleColumns.some((column: TableColumn) => {
    if (column.code !== columnCode) return false;
    if (columnCode === 'statistic' && column.type === 'Adaptable') {
      return column.stat_code === statCode;
    }
    return true;
  });

  if (!isVisible) return null;

  return <>{children}</>;
}

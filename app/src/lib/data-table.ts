import type {
  ExtendedColumnFilter,
  FilterOperator,
  FilterVariant,
} from "@/types/data-table";
import type { Column } from "@tanstack/react-table";

import { dataTableConfig } from "@/config/data-table";

/** The pinned edge a column carries next to the scrolling columns (data-pinned-edge, styled by Table). */
export function getPinnedEdge<TData>(column: Column<TData>): "left" | "right" | undefined {
  const isPinned = column.getIsPinned();
  if (isPinned === "left" && column.getIsLastColumn("left")) return "left";
  if (isPinned === "right" && column.getIsFirstColumn("right")) return "right";
  return undefined;
}

export function getCommonPinningStyles<TData>({
  column,
  withBorder = false,
}: {
  column: Column<TData>;
  withBorder?: boolean;
}): React.CSSProperties {
  const isPinned = column.getIsPinned();
  const isLastLeftPinnedColumn =
    isPinned === "left" && column.getIsLastColumn("left");
  const isFirstRightPinnedColumn =
    isPinned === "right" && column.getIsFirstColumn("right");

  return {
    boxShadow: withBorder
      ? isLastLeftPinnedColumn
        ? "-4px 0 4px hsl(var(--border)) inset"
        : isFirstRightPinnedColumn
          ? "4px 0 -4px hsl(var(--border)) inset"
          : undefined
      : undefined,
    left: isPinned === "left" ? `${column.getStart("left")}px` : undefined,
    right: isPinned === "right" ? `${column.getAfter("right")}px` : undefined,
    position: isPinned ? "sticky" : "relative",
    // A pinned cell covers the cells scrolling beneath it, so it is opaque white.
    background: isPinned ? "white" : undefined,
    width: column.getSize(),
    // Pinned columns keep their exact width: the sticky offsets of the next pinned column are
    // computed from it, and a column squeezed by the table layout would leave a gap.
    minWidth: isPinned ? column.getSize() : undefined,
    maxWidth: isPinned ? column.getSize() : undefined,
    zIndex: isPinned ? 1 : 0,
  };
}

export function getFilterOperators(filterVariant: FilterVariant) {
  const operatorMap: Record<
    FilterVariant,
    { label: string; value: FilterOperator }[]
  > = {
    text: dataTableConfig.textOperators,
    number: dataTableConfig.numericOperators,
    range: dataTableConfig.numericOperators,
    date: dataTableConfig.dateOperators,
    dateRange: dataTableConfig.dateOperators,
    boolean: dataTableConfig.booleanOperators,
    select: dataTableConfig.selectOperators,
    multiSelect: dataTableConfig.multiSelectOperators,
  };

  return operatorMap[filterVariant] ?? dataTableConfig.textOperators;
}

export function getDefaultFilterOperator(filterVariant: FilterVariant) {
  const operators = getFilterOperators(filterVariant);

  return operators[0]?.value ?? (filterVariant === "text" ? "iLike" : "eq");
}

export function getValidFilters<TData>(
  filters: ExtendedColumnFilter<TData>[],
): ExtendedColumnFilter<TData>[] {
  return filters.filter(
    (filter) =>
      filter.operator === "isEmpty" ||
      filter.operator === "isNotEmpty" ||
      (Array.isArray(filter.value)
        ? filter.value.length > 0
        : filter.value !== "" &&
          filter.value !== null &&
          filter.value !== undefined),
  );
}

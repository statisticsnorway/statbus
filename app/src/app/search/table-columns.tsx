"use client";

import {
  createContext,
  useContext,
  ReactNode,
  useEffect,
  useMemo,
  useState,
  useCallback,
} from "react";
import { isEqual } from "moderndash";
import {
  TableColumn,
  TableColumns,
  AdaptableTableColumn,
  ColumnProfile,
} from "./search.d";
import { useBaseData } from "../BaseDataClient";
import { Tables } from "@/lib/database.types";

const COLUMN_LOCALSTORAGE_NAME = "search-columns-state";

interface TableColumnsContextType {
  columns: TableColumns;
  visibleColumns: TableColumn[];
  toggleColumn: (column: TableColumn) => void;
  profiles: Record<ColumnProfile, TableColumn[]>;
  setProfile: (profile: ColumnProfile) => void;
  headerRowSuffix: string;
  headerCellSuffix: (column: TableColumn) => string;
  bodyRowSuffix: (unit: Tables<"statistical_unit">) => string;
  bodyCellSuffix: (
    unit: Tables<"statistical_unit">,
    column: TableColumn
  ) => string;
}

const TableColumnsContext = createContext<TableColumnsContextType | undefined>(
  undefined
);

export function TableColumnsProvider({ children }: { children: ReactNode }) {
  const { statDefinitions } = useBaseData();

  const available_columns: TableColumn[] = useMemo(() => {
    const statisticColumns: AdaptableTableColumn[] = statDefinitions.map(
      (statDefinition) =>
        ({
          type: "Adaptable",
          code: "statistic",
          stat_code: statDefinition.code!,
          label: statDefinition.name!,
          visible: statDefinition.priority! <= 1,
          profiles:
            statDefinition.priority === 1
              ? ["Brief", "Regular", "All"]
              : statDefinition.priority === 2
                ? ["Regular", "All"]
                : ["All"],
        }) as AdaptableTableColumn
    );

    if (statDefinitions === undefined) {
      return [];
    } else {
      return [
        { type: "Always", code: "name", label: "Name" },
        {
          type: "Adaptable",
          code: "activity_section",
          label: "Activity Section",
          visible: true,
          stat_code: null,
          profiles: ["Brief", "All"],
        },
        {
          type: "Adaptable",
          code: "activity",
          label: "Activity",
          visible: false,
          stat_code: null,
          profiles: ["Regular", "All"],
        },
        {
          type: "Adaptable",
          code: "secondary_activity",
          label: "Secondary Activity",
          visible: false,
          stat_code: null,
          profiles: ["Regular", "All"],
        },
        {
          type: "Adaptable",
          code: "top_region",
          label: "Top Region",
          visible: true,
          stat_code: null,
          profiles: ["Brief", "All"],
        },
        {
          type: "Adaptable",
          code: "region",
          label: "Region",
          visible: false,
          stat_code: null,
          profiles: ["Regular", "All"],
        },
        ...statisticColumns,
        {
          type: "Adaptable",
          code: "unit_counts",
          label: "Unit Counts",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "sector",
          label: "Sector",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "legal_form",
          label: "Legal Form",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "physical_address",
          label: "Address",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "birth_date",
          label: "Birth Date",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "death_date",
          label: "Death Date",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "status",
          label: "Status",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "unit_size",
          label: "Unit Size",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
        {
          type: "Adaptable",
          code: "data_sources",
          label: "Data Source",
          visible: false,
          stat_code: null,
          profiles: ["All"],
        },
      ];
    }
  }, [statDefinitions]);

  const [columns, setColumns] = useState<TableColumns>([]);

  // Update columns and keep user preferences
  const updateColumnsWithPreferences = useCallback(
    (userColumns: AdaptableTableColumn[] = []): TableColumns => {
      return available_columns.map((col) => {
        if (col.type === "Adaptable") {
          const userColumn = userColumns.find(
            (userCol) =>
              userCol.type === "Adaptable" &&
              userCol.code === col.code &&
              userCol.stat_code === col.stat_code
          );
          return { ...col, visible: userColumn?.visible ?? col.visible };
        }
        return col;
      });
    },
    [available_columns]
  );

  useEffect(() => {
    const fallbackColumns = updateColumnsWithPreferences();
    if (fallbackColumns.length === 0) {
      return;
    }

    // Try loading from localStorage first
    try {
      const saved = localStorage.getItem(COLUMN_LOCALSTORAGE_NAME);
      const savedColumns = saved ? JSON.parse(saved) : [];
      const currentColumns = updateColumnsWithPreferences(savedColumns);
      setColumns(currentColumns);
      if (!isEqual(savedColumns, currentColumns)) {
        localStorage.setItem(
          COLUMN_LOCALSTORAGE_NAME,
          JSON.stringify(currentColumns)
        );
      }
    } catch (e) {
      console.error("Failed to parse stored columns state:", e);
      localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
      setColumns(fallbackColumns);
    }

    // Listen for changes in other tabs
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === COLUMN_LOCALSTORAGE_NAME && e.newValue) {
        try {
          const updatedPreferences = JSON.parse(e.newValue);
          const updatedColumns =
            updateColumnsWithPreferences(updatedPreferences);
          setColumns(updatedColumns);
        } catch (e) {
          console.error("Failed to parse columns state from storage event:", e);
          localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
          setColumns(fallbackColumns);
        }
      }
    };

    window.addEventListener("storage", handleStorageChange);
    return () => window.removeEventListener("storage", handleStorageChange);
  }, [updateColumnsWithPreferences]);

  const toggleColumn = useCallback(
    (column: TableColumn) => {
      const newColumns = columns.map((col) => {
        if (
          col.type === "Adaptable" &&
          column.type == "Adaptable" &&
          col.code === column.code &&
          column.stat_code === col.stat_code
        ) {
          return { ...col, visible: !col.visible };
        }
        return col;
      });

      setColumns(newColumns);

      // Only store in localStorage if different from defaults
      if (!isEqual(newColumns, available_columns)) {
        localStorage.setItem(
          COLUMN_LOCALSTORAGE_NAME,
          JSON.stringify(newColumns)
        );
      } else {
        localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
      }
    },
    [columns, available_columns]
  );

  // Standardise how to create keys for UI updates
  const columnSuffix = (column: TableColumn) => {
    return `${column.code}${column.type === "Adaptable" && column.code === "statistic" ? `-${column.stat_code}` : ""}`;
  };

  const visibleColumns = useMemo(() => {
    return columns.filter((c) => c.type === "Always" || c.visible);
  }, [columns]);

  const visibleColumnsSuffix = useMemo(() => {
    const suffix = visibleColumns.map((c) => columnSuffix(c)).join("-");
    return suffix;
  }, [visibleColumns]);

  const unitSuffix = (unit: Tables<"statistical_unit">) => {
    return `${unit.unit_type}-${unit.unit_id}-${unit.valid_from}`;
  };

  const headerRowSuffix = visibleColumnsSuffix;
  const headerCellSuffix = columnSuffix;
  const bodyRowSuffix = (unit: Tables<"statistical_unit">) => {
    return `${unitSuffix(unit)}-${visibleColumnsSuffix}`;
  };
  const bodyCellSuffix = (
    unit: Tables<"statistical_unit">,
    column: TableColumn
  ) => {
    return `${unitSuffix(unit)}-${columnSuffix(column)}`;
  };

  const profiles: Record<ColumnProfile, TableColumns> = useMemo(
    () => ({
      Brief: columns.map((col) => ({
        ...col,
        ...(col.type === "Adaptable" &&
          "profiles" in col && {
            visible: col.profiles.includes("Brief"),
          }),
      })),
      Regular: columns.map((col) => ({
        ...col,
        ...(col.type === "Adaptable" &&
          "profiles" in col && {
            visible: col.profiles.includes("Regular"),
          }),
      })),
      All: columns.map((col) => ({
        ...col,
        ...(col.type === "Adaptable" &&
          "profiles" in col && {
            visible: col.profiles.includes("All"),
          }),
      })),
    }),
    [columns]
  );

  const setProfile = useCallback(
    (profile: ColumnProfile) => {
      // Update column visibility based on profile
      const newColumns = columns.map((col) => {
        if (col.type === "Adaptable" && "profiles" in col) {
          const shouldBeVisible = col.profiles.includes(profile);
          return { ...col, visible: shouldBeVisible };
        }
        return col;
      });

      setColumns(newColumns);
      if (!isEqual(newColumns, available_columns)) {
        localStorage.setItem(
          COLUMN_LOCALSTORAGE_NAME,
          JSON.stringify(newColumns)
        );
      } else {
        localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
      }
    },
    [columns, available_columns]
  );

  const value = {
    columns,
    visibleColumns,
    toggleColumn,
    profiles,
    setProfile,
    headerRowSuffix,
    headerCellSuffix,
    bodyRowSuffix,
    bodyCellSuffix,
  };

  return (
    <TableColumnsContext.Provider value={value}>
      {children}
    </TableColumnsContext.Provider>
  );
}

export function useTableColumns() {
  const context = useContext(TableColumnsContext);
  if (context === undefined) {
    throw new Error(
      "useTableColumns must be used within a TableColumnsProvider"
    );
  }
  return context;
}

import { useEffect, useMemo, useState, useCallback } from 'react';
import { isEqual } from 'moderndash';
import { TableColumn, TableColumns, AdaptableTableColumn } from './search.d';
import { useBaseData } from '../BaseDataClient';
import { Tables } from '@/lib/database.types';

const COLUMN_LOCALSTORAGE_NAME = 'table-columns-state';

export function useTableColumns() {
  const { statDefinitions, externalIdentTypes } = useBaseData();

  const default_columns: TableColumn[] = useMemo(() => {
    const statisticColumns: AdaptableTableColumn[] =
      statDefinitions.map(statDefinition => ({
        type: 'Adaptable',
        code: 'statistic',
        stat_code: statDefinition.code!,
        label: statDefinition.name!,
        visible: true
      }));

    if (statDefinitions === undefined) {
      return [];
    } else {
      return [
        { type: 'Always', code: 'name', label: 'Name' },
        { type: 'Adaptable', code: 'activity', label: 'Activity', visible: true, stat_code: null },
        { type: 'Adaptable', code: 'region', label: 'Region', visible: true, stat_code: null },
        ...statisticColumns,
        { type: 'Adaptable', code: 'sector', label: 'Sector', visible: true, stat_code: null },
        { type: 'Adaptable', code: 'data_sources', label: 'Data Source', visible: true, stat_code: null },
      ];
    }
  }, [statDefinitions]);


  const [columns, setColumns] = useState<TableColumns>([]);

  useEffect(() => {
    if (default_columns.length === 0) {
      return; // Wait for default columns to be available
    }

    // Try loading from localStorage first
    const saved = localStorage.getItem(COLUMN_LOCALSTORAGE_NAME);
    if (saved) {
      try {
        const state = JSON.parse(saved);
        setColumns(state);
      } catch (e) {
        console.error('Failed to parse stored columns state:', e);
        localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
        setColumns(default_columns); // Fall back to defaults on error
      }
      return;
    }

    // Fall back to default columns if no localStorage data
    setColumns(default_columns);

    // Listen for changes in other tabs
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === COLUMN_LOCALSTORAGE_NAME && e.newValue) {
        try {
          const newState = JSON.parse(e.newValue);
          setColumns(newState);
        } catch (e) {
          console.error('Failed to parse columns state from storage event:', e);
          localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
          setColumns(default_columns); // Fall back to defaults on error
        }
      }
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, [default_columns]);

  const isDefaultState = useMemo(() => {
    return isEqual(columns, default_columns);
  }, [columns, default_columns]);

  const resetColumns = useCallback(() => {
    setColumns(default_columns);
    localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
  }, [default_columns]);

  const toggleColumn = useCallback((column: TableColumn) => {
    const newColumns = columns.map(col => {
      if (col.type === 'Adaptable' && column.type == 'Adaptable'
        && col.code === column.code
        && column.stat_code === col.stat_code
      ) {
        return { ...col, visible: !col.visible };
      }
      return col;
    });

    setColumns(newColumns);

    // Only store in localStorage if different from defaults
    if (!isEqual(newColumns, default_columns)) {
      localStorage.setItem(COLUMN_LOCALSTORAGE_NAME, JSON.stringify(newColumns));
    } else {
      localStorage.removeItem(COLUMN_LOCALSTORAGE_NAME);
    }
  }, [columns, default_columns]);

  // Force re-render when columns change
  const visibleColumnsSuffix = useMemo(() => {
    const suffix =
      columns
        .filter(c => c.type === 'Always' || c.visible)
        .map(c => `${c.code}${c.type === 'Adaptable' && c.code === 'statistic' ? `-${c.stat_code}` : ''}`)
        .join('-');
    return suffix;
  }, [columns]);
  const columnSuffix = (column: TableColumn) => {
    return `${column.code}${column.type === 'Adaptable' && column.code === 'statistic' ? `-${column.stat_code}` : ''}`
  };
  const unitSuffix = (unit: Tables<"statistical_unit">) => {
    return `${unit.unit_type}-${unit.unit_id}-${unit.valid_from}`
  };

  const headerRowSuffix = visibleColumnsSuffix;
  const headerCellSuffix = columnSuffix;
  const bodyRowSuffix = (unit: Tables<"statistical_unit">) => {
    return `${unitSuffix(unit)}-${visibleColumnsSuffix}`
  };
  const bodyCellSuffix = (unit: Tables<"statistical_unit">, column: TableColumn) => {
    return `${unitSuffix(unit)}-${columnSuffix(column)}`
  };

  return {
    columns,
    toggleColumn,
    resetColumns,
    isDefaultState,
    headerRowSuffix,
    headerCellSuffix,
    bodyRowSuffix,
    bodyCellSuffix,
  };
}

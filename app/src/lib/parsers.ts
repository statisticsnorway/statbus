import { createParser } from "nuqs/server";
import { z } from "zod";

import { dataTableConfig } from "@/config/data-table";

import type {
  ExtendedColumnFilter,
  ExtendedColumnSort,
} from "@/types/data-table";

// Decoded URL-state resource budgets: 64Ki UTF-16 code units bounds JSON decoding,
// 128 rows leaves headroom beyond typical table controls, and 256 selected values
// supports broad multi-select filters while bounding Zod 3's issue accumulation.
// The raw limit measures JavaScript string length, not HTTP or UTF-8 bytes.
const queryStateLimits = {
  rawCodeUnits: 64 * 1024,
  items: 128,
  filterValues: 256,
};

function parseQueryArray(value: string): unknown[] | null {
  if (value.length > queryStateLimits.rawCodeUnits) return null;

  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed) || parsed.length > queryStateLimits.items) {
    return null;
  }

  return parsed;
}

const sortingItemSchema = z.object({
  id: z.string(),
  desc: z.boolean(),
});

export const getSortingStateParser = <TData>(
  columnIds?: string[] | Set<string>
) => {
  const validKeys = columnIds
    ? columnIds instanceof Set
      ? columnIds
      : new Set(columnIds)
    : null;

  return createParser({
    parse: (value) => {
      try {
        const parsed = parseQueryArray(value);
        if (!parsed) return null;

        const result = z.array(sortingItemSchema).safeParse(parsed);

        if (!result.success) return null;

        if (
          validKeys &&
          result.data.some((item) => !validKeys.has(item.id as string))
        ) {
          return null;
        }

        return result.data as ExtendedColumnSort<TData>[];
      } catch {
        return null;
      }
    },
    serialize: (value) => JSON.stringify(value),
    eq: (a, b) =>
      a.length === b.length &&
      a.every(
        (item, index) =>
          item.id === b[index]?.id && item.desc === b[index]?.desc
      ),
  });
};

const filterItemSchema = z.object({
  id: z.string(),
  value: z.union([z.string(), z.array(z.string())]),
  variant: z.enum(dataTableConfig.filterVariants),
  operator: z.enum(dataTableConfig.operators),
  filterId: z.string(),
});

export type FilterItemSchema = z.infer<typeof filterItemSchema>;

export const getFiltersStateParser = <TData>(
  columnIds?: string[] | Set<string>
) => {
  const validKeys = columnIds
    ? columnIds instanceof Set
      ? columnIds
      : new Set(columnIds)
    : null;

  return createParser({
    parse: (value) => {
      try {
        const parsed = parseQueryArray(value);
        if (!parsed) return null;

        if (
          parsed.some(
            (item) =>
              item !== null &&
              typeof item === "object" &&
              "value" in item &&
              Array.isArray(item.value) &&
              item.value.length > queryStateLimits.filterValues
          )
        ) {
          return null;
        }

        const result = z.array(filterItemSchema).safeParse(parsed);

        if (!result.success) return null;

        if (validKeys && result.data.some((item) => !validKeys.has(item.id))) {
          return null;
        }

        return result.data as ExtendedColumnFilter<TData>[];
      } catch {
        return null;
      }
    },
    serialize: (value) => JSON.stringify(value),
    eq: (a, b) =>
      a.length === b.length &&
      a.every(
        (filter, index) =>
          filter.id === b[index]?.id &&
          filter.value === b[index]?.value &&
          filter.variant === b[index]?.variant &&
          filter.operator === b[index]?.operator
      ),
  });
};

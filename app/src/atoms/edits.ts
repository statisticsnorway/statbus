import { Tables } from "@/lib/database.types";
import { isEqual } from "moderndash";
import { atom, useAtomValue, useSetAtom } from "jotai";
import { atomWithRefresh, loadable, selectAtom } from "jotai/utils";
import { useCallback } from "react";
import { authStateForDataFetchingAtom } from "./auth";
import { restClientAtom } from "./rest-client";

export interface EditTarget {
  fieldId: string | null;
  validFrom?: string | null;
  validTo?: string | null;
  dataSourceId?: string | null;
  editComment?: string | null;
}

export const initialEditAtom: EditTarget = {
  fieldId: null,
};

export const currentEditAtom = atom<EditTarget>(initialEditAtom);

export const setEditTargetAtom = atom(
  null,
  (
    get,
    set,
    fieldId: string | null,
    options?: { validFrom?: string | null; validTo?: string | null }
  ) => {
    set(currentEditAtom, (prev) => ({
      ...prev,
      fieldId: fieldId,
      validFrom: options?.validFrom ?? null,
      validTo: options?.validTo ?? null,
    }));
  }
);

export const exitEditModeAtom = atom(null, (get, set) => {
  set(currentEditAtom, initialEditAtom);
});

export const setEditValidFromDateAtom = atom(
  null,
  (get, set, date: string | null) => {
    set(currentEditAtom, (prev) => ({ ...prev, validFrom: date }));
  }
);

export const setEditValidToDateAtom = atom(
  null,
  (get, set, date: string | null) => {
    set(currentEditAtom, (prev) => ({ ...prev, validTo: date }));
  }
);

export const setEditDataSourceIdAtom = atom(
  null,
  (get, set, dataSourceId: string | null) => {
    set(currentEditAtom, (prev) => ({
      ...prev,
      dataSourceId: dataSourceId,
    }));
  }
);

export const setEditCommentAtom = atom(
  null,
  (get, set, comment: string | null) => {
    set(currentEditAtom, (prev) => ({ ...prev, editComment: comment }));
  }
);

export const useEditManager = () => {
  const currentEdit = useAtomValue(currentEditAtom);
  const exitEditMode = useSetAtom(exitEditModeAtom);
  const doSetEditTarget = useSetAtom(setEditTargetAtom);
  const doSetValidFrom = useSetAtom(setEditValidFromDateAtom);
  const doSetValidTo = useSetAtom(setEditValidToDateAtom);
  const doSetDataSourceId = useSetAtom(setEditDataSourceIdAtom);
  const doSetEditComment = useSetAtom(setEditCommentAtom);
  const setEditTarget = useCallback(
    (
      fieldId: string | null,
      options?: { validFrom?: string | null; validTo?: string | null }
    ) => {
      doSetEditTarget(fieldId, options);                          
    },
    [doSetEditTarget]
  );
  const setEditValidFrom = useCallback(
    (date: string | null) => {
      doSetValidFrom(date);
    },
    [doSetValidFrom]
  );

  const setEditValidTo = useCallback(
    (date: string | null) => {
      doSetValidTo(date);
    },
    [doSetValidTo]
  );

  const setEditDataSourceId = useCallback(
    (id: string | null) => {
      doSetDataSourceId(id);
    },
    [doSetDataSourceId]
  );

  const setEditComment = useCallback(
    (comment: string | null) => {
      doSetEditComment(comment);
    },
    [doSetEditComment]
  );

  return {
    currentEdit,
    setEditTarget,
    exitEditMode,
    setEditValidFrom,
    setEditValidTo,
    setEditDataSourceId,
    setEditComment,
  };
};

export interface DetailsPageData {
  dataSources: Tables<"data_source_available">[];
  regions: Tables<"region">[];
  countries: Tables<"country">[];
  status: Tables<"status">[];
  activityCategories: Tables<"activity_category_available">[];
  legalForms: Tables<"legal_form_available">[];
  sectors: Tables<"sector_available">[];
  unitSizes: Tables<"unit_size_available">[];
}
const initialDetailsPageData: DetailsPageData = {
  dataSources: [],
  regions: [],
  countries: [],
  status: [],
  activityCategories: [],
  legalForms: [],
  sectors: [],
  unitSizes: [],
};

const detailsPageDataPromiseAtom = atomWithRefresh<Promise<DetailsPageData>>(
  async (get) => {
    const authState = get(authStateForDataFetchingAtom);
    const client = get(restClientAtom);

    if (authState !== "authenticated" || !client) {
      return initialDetailsPageData;
    }

    try {
      const [
        dataSourcesResult,
        regionsResult,
        countriesResult,
        statusResult,
        activityCategoriesResult,
        legalFormsResult,
        sectorsResult,
        unitSizesResult,
      ] = await Promise.all([
        client.from("data_source_available").select(),
        client.from("region").select(),
        client.from("country").select(),
        client.from("status").select(),
        client.from("activity_category_available").select(),
        client.from("legal_form_available").select(),
        client.from("sector_available").select(),
        client.from("unit_size_available").select(),
      ]);
      // TODO: Add error handling for each result
      return {
        dataSources: dataSourcesResult.data || [],
        regions: regionsResult.data || [],
        countries: countriesResult.data || [],
        status: statusResult.data || [],
        activityCategories: activityCategoriesResult.data || [],
        legalForms: legalFormsResult.data || [],
        sectors: sectorsResult.data || [],
        unitSizes: unitSizesResult.data || [],
      };
    } catch (error) {
      console.error(
        "detailsPageDataPromiseAtom: Failed to fetch details page data:",
        error
      );
      return initialDetailsPageData;
    }
  }
);

const detailsPageDataLoadableAtom = loadable(detailsPageDataPromiseAtom);

function areDetailsPageDataResultsEqual(
  a: DetailsPageData & { loading: boolean; error: string | null },
  b: DetailsPageData & { loading: boolean; error: string | null }
): boolean {
  if (a.loading !== b.loading) return false;
  if (a.error !== b.error) return false;
  return isEqual(a, b);
}

const detailsPageDataUnstableAtom = atom<
  DetailsPageData & { loading: boolean; error: string | null }
>((get) => {
  const loadableState = get(detailsPageDataLoadableAtom);
  switch (loadableState.state) {
    case "loading":
      const dataWhileLoading =
        (loadableState as { data?: DetailsPageData }).data ??
        initialDetailsPageData;
      return { ...dataWhileLoading, loading: true, error: null };
    case "hasError":
      const error = loadableState.error;
      return {
        ...initialDetailsPageData,
        loading: false,
        error: error instanceof Error ? error.message : String(error),
      };
    case "hasData":
      return { ...loadableState.data, loading: false, error: null };
    default:
      return {
        ...initialDetailsPageData,
        loading: false,
        error: "Unknown loadable state",
      };
  }
});

export const detailsPageDataAtom = selectAtom(
  detailsPageDataUnstableAtom,
  (v) => v,
  areDetailsPageDataResultsEqual
);

export const useDetailsPageData = () => {
  return useAtomValue(detailsPageDataAtom);
};

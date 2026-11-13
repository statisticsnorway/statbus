import { Tables } from "@/lib/database.types";
import { describeError } from "@/lib/error-format";
import { isEqual } from "moderndash";
import { atom, useAtomValue, useSetAtom } from "jotai";
import { atomWithRefresh, loadable, selectAtom } from "jotai/utils";
import { useCallback } from "react";
import { authStateForDataFetchingAtom } from "./auth";
import { restClientAtom } from "./rest-client";

/**
 * The field being edited and the period its change applies to. The period comes
 * from a time frame (public.time_frame, frameIdent): starting an edit takes the
 * selected frame, choosing another frame in the form re-derives the dates from
 * it (useStartEdit). The details (Data Source, Valid From, Valid To) refine it.
 * source and shownValue are kept so a frame change can re-read the field's rows.
 */
export interface EditTarget {
  fieldId: string | null;
  frameIdent?: string | null;
  validFrom?: string | null;
  validTo?: string | null;
  dataSourceId?: string | null;
  editComment?: string | null;
  source?: import("@/components/form/read-edit-range").EditFieldSource;
  shownValue?: unknown;
  /**
   * Remove mode (STATBUS-611): the ticked timeline pieces, by index into the
   * field's pieces per frame. Entering the Timeline in Remove mode ticks the
   * pieces inside the Frame view's frame or dates; going back to the Frame
   * view drops the ticks (owner 2026-11-13). Absent or null: the edit changes
   * values (Save).
   */
  removing?: number[] | null;
  /**
   * The Time frame panel's view: "frame" (a frame or specific dates) or
   * "timeline" (ticked stretches). Absent: frame. Change and Remove both
   * follow it, so it lives with the edit, not in the panel.
   */
  view?: "frame" | "timeline";
  /** In the Frame view: dated by the frame (default) or by specific dates. */
  validityChoice?: "frame" | "dates";
}

export const initialEditAtom: EditTarget = {
  fieldId: null,
};

export const currentEditAtom = atom<EditTarget>(initialEditAtom);

export type EditTargetOptions = Omit<EditTarget, "fieldId">;

export const setEditTargetAtom = atom(
  null,
  (get, set, fieldId: string | null, options?: EditTargetOptions) => {
    set(currentEditAtom, () => ({
      fieldId: fieldId,
      frameIdent: options?.frameIdent ?? null,
      validFrom: options?.validFrom ?? null,
      validTo: options?.validTo ?? null,
      dataSourceId: options?.dataSourceId ?? null,
      editComment: options?.editComment ?? null,
      source: options?.source,
      shownValue: options?.shownValue,
    }));
  }
);

/**
 * Moves the open edit to another frame and the dates derived from it. The data
 * source and comment are those of the row the edit now starts in, when read.
 */
export const setEditFrameAtom = atom(
  null,
  (
    get,
    set,
    frame: { frameIdent: string; validFrom: string | null; validTo: string | null; dataSourceId?: string | null; editComment?: string | null }
  ) => {
    set(currentEditAtom, (prev) => ({ ...prev, ...frame }));
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

/** Turns Remove mode on (no pieces ticked), sets its ticks, or turns it off (null). */
export const setEditRemovingAtom = atom(
  null,
  (get, set, removing: number[] | null) => {
    set(currentEditAtom, (prev) => ({ ...prev, removing }));
  }
);

/**
 * Sets the panel's view. In Remove mode the ticks are given by the caller: the
 * Timeline starts from the Frame view's period (piecesInPeriod); the Frame
 * view drops them and shows its own frame or dates again.
 */
export const setEditViewAtom = atom(
  null,
  (get, set, view: "frame" | "timeline", removing?: number[]) => {
    set(currentEditAtom, (prev) => ({
      ...prev,
      view,
      removing: prev.removing != null ? (removing ?? []) : prev.removing,
    }));
  }
);

export const setEditValidityChoiceAtom = atom(
  null,
  (get, set, validityChoice: "frame" | "dates") => {
    set(currentEditAtom, (prev) => ({ ...prev, validityChoice }));
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
  const setEditFrame = useSetAtom(setEditFrameAtom);
  const doSetValidFrom = useSetAtom(setEditValidFromDateAtom);
  const doSetValidTo = useSetAtom(setEditValidToDateAtom);
  const doSetDataSourceId = useSetAtom(setEditDataSourceIdAtom);
  const doSetEditComment = useSetAtom(setEditCommentAtom);
  const setEditRemoving = useSetAtom(setEditRemovingAtom);
  const setEditView = useSetAtom(setEditViewAtom);
  const setEditValidityChoice = useSetAtom(setEditValidityChoiceAtom);
  const setEditTarget = useCallback(
    (fieldId: string | null, options?: EditTargetOptions) => {
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
    setEditFrame,
    exitEditMode,
    setEditValidFrom,
    setEditValidTo,
    setEditDataSourceId,
    setEditComment,
    setEditRemoving,
    setEditView,
    setEditValidityChoice,
  };
};

export interface DetailsPageData {
  dataSources: Tables<"data_source_enabled">[];
  regions: Tables<"region">[];
  countries: Tables<"country">[];
  /** settings.country_id: the installation's own country, listed first. */
  domesticCountryId: number | null;
  status: Tables<"status">[];
  activityCategories: Tables<"activity_category_enabled">[];
  legalForms: Tables<"legal_form_enabled">[];
  sectors: Tables<"sector_enabled">[];
  unitSizes: Tables<"unit_size_enabled">[];
}
const initialDetailsPageData: DetailsPageData = {
  dataSources: [],
  regions: [],
  countries: [],
  domesticCountryId: null,
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
        settingsResult,
      ] = await Promise.all([
        client.from("data_source_enabled").select(),
        client.from("region").select(),
        client.from("country").select(),
        client.from("status").select().eq("enabled", true),
        client.from("activity_category_enabled").select(),
        client.from("legal_form_enabled").select(),
        client.from("sector_enabled").select(),
        client.from("unit_size_enabled").select(),
        client.from("settings").select("country_id").limit(1),
      ]);
      // TODO: Add error handling for each result
      return {
        dataSources: dataSourcesResult.data || [],
        regions: regionsResult.data || [],
        countries: countriesResult.data || [],
        domesticCountryId: settingsResult.data?.[0]?.country_id ?? null,
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
        error: describeError(error),
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

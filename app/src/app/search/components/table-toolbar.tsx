"use client";
import { useCallback } from "react";
import { Input } from "@/components/ui/input";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useSearchContext } from "@/app/search/use-search-context";

export default function TableToolbar() {
  const {
    search: { queries },
    dispatch,
  } = useSearchContext();

  const hasAnyFilterSelected = Object.keys(queries).length > 0;

  const createFilterComponent = useCallback(
    ({ type, name, label, options, selected, operator }: SearchFilter) => {
      switch (type) {
        case "radio":
          return (
            <OptionsFilter
              className="p-2 h-9"
              key={name}
              title={label}
              options={options}
              selectedValues={selected}
              onToggle={({ value }) =>
                dispatch({
                  type: "toggle_radio_option",
                  payload: { name, value },
                })
              }
              onReset={() => dispatch({ type: "reset", payload: { name } })}
            />
          );
        case "options":
          return (
            <OptionsFilter
              className="p-2 h-9"
              key={name}
              title={label}
              options={options}
              selectedValues={selected}
              onToggle={({ value }) =>
                dispatch({ type: "toggle_option", payload: { name, value } })
              }
              onReset={() => dispatch({ type: "reset", payload: { name } })}
            />
          );
        case "conditional":
          return (
            <ConditionalFilter
              className="p-2 h-9"
              key={name}
              title={label}
              selected={{ operator, value: selected[0] }}
              onChange={({ operator, value }) =>
                dispatch({
                  type: "set_condition",
                  payload: { name, value, operator },
                })
              }
              onReset={() => dispatch({ type: "reset", payload: { name } })}
            />
          );
        case "search":
          return (
            <Input
              key={name}
              type="text"
              id={`search-prompt-${name}`}
              placeholder={label}
              className="h-9 w-full md:max-w-[200px]"
              value={selected[0] ?? ""}
              onChange={(e) => {
                dispatch({
                  type: "set_search",
                  payload: { name, value: e.target.value },
                });
              }}
            />
          );
        default:
          return null;
      }
    },
    [dispatch]
  );

  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      {hasAnyFilterSelected && (
        <ResetFilterButton
          className="h-9 p-2"
          onReset={() => dispatch({ type: "reset_all" })}
        />
      )}
    </div>
  );
}

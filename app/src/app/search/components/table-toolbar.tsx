import { useCallback } from "react";
import { Input } from "@/components/ui/input";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";
import { ConditionalFilter } from "@/app/search/components/conditional-filter";
import { useSearchContext } from "@/app/search/search-provider";

export default function TableToolbar() {
  const {
    search: { filters },
    dispatch,
  } = useSearchContext();
  const hasAnyFilterSelected = filters.some(
    ({ selected }) => selected?.[0]?.toString().length
  );

  const createFilterComponent = useCallback(
    ({ type, name, label, options, selected, operator }: SearchFilter) => {
      switch (type) {
        case "radio":
          return (
            <OptionsFilter
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
              className="ml-2 h-10 w-[100px]"
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
    <div className="-m-2 flex flex-wrap items-center space-x-2">
      {filters.map(createFilterComponent)}
      {hasAnyFilterSelected && (
        <ResetFilterButton
          className="m-2 h-10"
          onReset={() => dispatch({ type: "reset_all" })}
        />
      )}
    </div>
  );
}

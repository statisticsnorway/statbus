import {Tables} from "@/lib/database.types";
import {useReducer} from "react";
import type {SearchFilter, SearchFilterActions} from "@/app/search/search.types";
import {useSearchParams} from "next/navigation";

function searchFilterReducer(state: SearchFilter[], action: SearchFilterActions): SearchFilter[] {
  switch (action.type) {
    case "toggle_option": {
      const {name, value} = action.payload
      return state.map(f =>
        f.name === name ? {
          ...f,
          selected: f.selected.includes(value) ? f.selected.filter(id => id !== value) : [...f.selected, value]
        } : f
      )
    }
    case "toggle_radio_option": {
      const {name, value} = action.payload
      return state.map(f => f.name === name ? {...f, selected: f.selected.find(id => id == value) ? [] : [value]} : f)
    }
    case "set_condition": {
      const {name, value, condition} = action.payload
      return state.map(f => f.name === name ? {...f, selected: [value], condition} : f)
    }
    case "set_search": {
      const {name, value} = action.payload
      return state.map(f => f.name === name ? {...f, selected: [value]} : f)
    }
    case "reset": {
      const {name} = action.payload
      return state.map(f => f.name === name ? {...f, selected: []} : f)
    }
    case "reset_all":
      return state.map(f => ({...f, selected: []}))
    default:
      return state
  }
}

interface FilterOptions {
  activityCategories: Tables<"activity_category_available">[],
  regions: Tables<"region_used">[]
  statisticalVariables: Tables<"stat_definition">[]
}

const PHYSICAL_REGION_PATH = 'physical_region_path';
const PRIMARY_ACTIVITY_CATEGORY_PATH = 'primary_activity_category_path';

export const useFilter = ({regions = [], activityCategories = [], statisticalVariables = []}: FilterOptions) => {
  const urlSearchParams = useSearchParams()
  const standardFilters: SearchFilter[] = [
    {
      type: "search",
      label: "Name",
      // Search is a vector field of name indexed for fast full text search.
      name: "search",
      selected: [],
      postgrestQuery: ({selected}) => generateFTSQuery(selected[0])
    },
    {
      type: "search",
      label: "Tax ID",
      name: "tax_reg_ident",
      selected: [],
      postgrestQuery: ({selected}) => selected[0] ? `eq.${selected[0]}` : null
    },
    {
      type: "options",
      label: "Type",
      name: "unit_type",
      options: [
          {label: "Legal Unit", value: "legal_unit"},
          {label: "Establishment", value: "establishment"},
          {label: "Enterprise", value: "enterprise"},
      ],
      selected: ["enterprise"],
      postgrestQuery: ({selected}) => selected.length ? `in.(${selected.join(',')})` : null
    },
    {
      type: "radio",
      name: "physical_region_path",
      label: "Region",
      options: regions.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(PHYSICAL_REGION_PATH) ? [urlSearchParams?.get(PHYSICAL_REGION_PATH) as string] : [],
      postgrestQuery: ({selected}) => selected.length ? `cd.${selected.join()}` : null
    },
    {
      type: "radio",
      name: "primary_activity_category_path",
      label: "Activity Category",
      options: activityCategories.map(({code, path, name}) => (
        {
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`
        }
      )),
      selected: urlSearchParams?.has(PRIMARY_ACTIVITY_CATEGORY_PATH) ? [urlSearchParams?.get(PRIMARY_ACTIVITY_CATEGORY_PATH) as string] : [],
      postgrestQuery: ({selected}) => selected.length ? `cd.${selected.join()}` : null
    }
  ];

  const statisticalVariableFilters: SearchFilter[] = statisticalVariables.map(variable => ({
    type: "conditional",
    name: variable.code,
    label: variable.name,
    selected: [],
    postgrestQuery: ({condition, selected}: SearchFilter) =>
      condition && selected.length ? `${condition}.${selected.join(',')}` : null
  }));

  return useReducer(searchFilterReducer, [...standardFilters, ...statisticalVariableFilters])
}

export function generateFTSQuery(prompt: string = ""): string | null {
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) => new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt)
  const uniqueWordsInPrompt = new Set(cleanedPrompt.match(/\b\w+\b/g) ?? []);
  const tsQuery = [...uniqueWordsInPrompt]
    .map(word => isNegated(word) ? `!'${word}':*` : `'${word}':*`)
    .join(' & ');

  return tsQuery ? `fts(simple).${tsQuery}` : null;
}

import { UNIT_TYPE } from "@/app/search/filtersV2/url-search-params";

export const createUnitTypeSearchFilter = (
  params: URLSearchParams
): SearchFilter => {
  const unitType = params.get(UNIT_TYPE);
  return {
    type: "options",
    label: "Type",
    name: UNIT_TYPE,
    options: [
      {
        label: "Legal Unit",
        value: "legal_unit",
        humanReadableValue: "Legal Unit",
        className: "bg-legal_unit-100",
      },
      {
        label: "Establishment",
        value: "establishment",
        humanReadableValue: "Establishment",
        className: "bg-establishment-100",
      },
      {
        label: "Enterprise",
        value: "enterprise",
        humanReadableValue: "Enterprise",
        className: "bg-enterprise-100",
      },
    ],
    selected: unitType?.split(",") ?? ["enterprise"],
  };
};

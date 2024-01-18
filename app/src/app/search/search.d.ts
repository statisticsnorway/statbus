type LegalUnit = {
  tax_reg_ident: string | null,
  name: string | null
}

type SearchFilterValue = string | number

type SearchFilterOption = {
  readonly label: string
  readonly value: SearchFilterValue
}

type SearchFilter = {
  readonly name: string
  readonly label: string
  options: SearchFilterOption[]
  selected: SearchFilterValue[]
}

type SearchFilterActionTypes = "toggle" | "reset" | "reset_all"

type SearchFilterAction = { type: SearchFilterActionTypes; payload?: { name: string, value: SearchFilterValue } };

type SearchResult = {
  legalUnits: LegalUnit[]
  count: number
}

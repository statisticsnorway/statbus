import { array, number, object, string, lazy, boolean } from 'yup'

import { predicateFields, predicateOperations, predicateComparison } from 'helpers/enums'
import getUid from 'helpers/getUid'

const fields = [...predicateFields.keys()]
const operations = [...predicateOperations.keys()]
const comparison = [-1, ...predicateComparison.keys()]

const clauseSchema = object({
  field: number()
    .oneOf(fields)
    .default(1),
  operation: number()
    .oneOf(operations)
    .default(1),
  value: string().ensure(),
  comparison: number()
    .oneOf(comparison)
    .default(1),
  selected: boolean().default(false),
  uid: number().required(),
})

const predicateSchema = object({
  clauses: array(clauseSchema).default([]),
  left: lazy(() => predicateSchema.nullable().default(undefined)),
  right: lazy(() => predicateSchema.nullable().default(undefined)),
  comparison: number()
    .oneOf(comparison)
    .default(1),
})

export function createClauseDefaults() {
  const clause = clauseSchema.default()
  clause.uid = getUid()
  return clause
}

export function createHeadClauseDefaults() {
  const clause = createClauseDefaults()
  clause.comparison = -1 // eslint-disable-line prefer-destructuring
  return clause
}

export const createDefaults = () => ({
  name: '',
  predicate: { ...predicateSchema.default(), clauses: [createHeadClauseDefaults()] },
  fields: [],
})

const defaults = createDefaults()
export const schema = object({
  name: string()
    .required('SampleFrameNameIsRequired')
    .default(defaults.name),
  predicate: predicateSchema.required('PredicateIsRequired').default(defaults.predicate),
  fields: array()
    .min(1, 'FieldsIsRequired')
    .required('FieldsIsRequired')
    .default(defaults.fields),
})

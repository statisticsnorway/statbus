import { array, number, object, string, lazy, boolean } from 'yup'

import { predicateFields } from '/helpers/config'
import { predicateComparison } from '/helpers/enums'
import getUid from '/helpers/getUid'

const fields = [...predicateFields.keys()]
const comparison = [...predicateComparison.keys()]

const clauseSchema = object({
  field: number()
    .oneOf(fields)
    .default(1),
  operation: number()
    .when('field', (field, schema) =>
      schema.oneOf(
        predicateFields.get(field).operations,
        'SomeClausesHasWrongOperationOnSelectedField',
      ))
    .default(1),
  comparison: number()
    .oneOf(comparison)
    .default(1),
  value: string()
    .required('ValuesIsRequired')
    .ensure(),
  selected: boolean().default(false),
  uid: number().required(),
})

const predicateSchema = object({
  clauses: array(clauseSchema).default([]),
  predicates: lazy(() => array(predicateSchema).default([])),
})

export function createClauseDefaults() {
  const clause = clauseSchema.default()
  clause.uid = getUid()
  return clause
}

export const createDefaults = () => ({
  name: '',
  description: '',
  predicate: {
    clauses: [createClauseDefaults()],
    predicates: [],
  },
  fields: [],
})

const defaults = createDefaults()
export const schema = object({
  name: string()
    .required('SampleFrameNameIsRequired')
    .default(defaults.name),
  description: string().default(defaults.description),
  predicate: predicateSchema.required('PredicateIsRequired').default(defaults.predicate),
  fields: array()
    .min(1, 'FieldsIsRequired')
    .required('FieldsIsRequired')
    .default(defaults.fields),
})

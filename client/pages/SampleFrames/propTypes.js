import { arrayOf, bool, number, oneOf, shape, string } from 'prop-types'

import { predicateFields } from '/client/helpers/config'
import { predicateComparison, predicateOperations } from '/client/helpers/enums'

const comparison = [...predicateComparison.keys()]
const operations = [...predicateOperations.keys()]
const fields = [...predicateFields.keys()]

export const clause = shape({
  field: oneOf(fields),
  operation: oneOf(operations),
  value: string,
  comparison: oneOf(comparison),
  selected: bool,
  uid: number.isRequired,
})

const predicateShape = { clauses: arrayOf(clause).isRequired }
predicateShape.predicates = arrayOf(shape(predicateShape))

export const predicate = shape(predicateShape)

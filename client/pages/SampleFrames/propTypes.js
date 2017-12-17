import { arrayOf, bool, number, oneOf, shape, string } from 'prop-types'

import { predicateComparison, predicateOperations, predicateFields } from 'helpers/enums'

const comparison = [-1, -2, ...predicateComparison.keys()]
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

const predicateShape = {
  clauses: arrayOf(clause).isRequired,
  comparison: oneOf(comparison),
}
predicateShape.left = shape(predicateShape)
predicateShape.right = shape(predicateShape)

export const predicate = shape(predicateShape)

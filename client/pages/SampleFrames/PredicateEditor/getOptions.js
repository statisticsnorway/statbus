import { predicateComparison, predicateFields, predicateOperations } from 'helpers/enums'

const headComparison = new Map([[-1, '-']])

export default (isHead, localize) => {
  const asOptions = pairs => [...pairs.entries()].map(p => ({ value: p[0], text: localize(p[1]) }))
  return {
    comparison: asOptions(isHead ? headComparison : predicateComparison),
    field: asOptions(predicateFields),
    operation: asOptions(predicateOperations),
  }
}

import { pipe, anyPass, isNil, isEmpty, any, values, not } from 'ramda'

export const nullsToUndefined = obj =>
  Object.entries(obj).reduce(
    (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
    {},
  )

export const stripNullableFields = fields => obj =>
  Object.entries(obj).reduce(
    (accum, [k, v]) =>
      fields.includes(k) && v === 0 ? accum : { ...accum, [k]: v },
      {},
  )

export const nonEmpty = pipe(anyPass([isNil, isEmpty]), not)

export const nonEmptyValues = pipe(values, any(nonEmpty))

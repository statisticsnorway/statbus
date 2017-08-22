export const nullsToUndefined = obj => Object.entries(obj).reduce(
  (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
  {},
)

export const stripNullableFields = nullableFields => statFields =>
  Object.entries(statFields).reduce(
    (accum, [k, v]) =>
      nullableFields.includes(k) && v === 0 ? accum : { ...accum, [k]: v },
      {},
)

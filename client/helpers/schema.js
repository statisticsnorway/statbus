const nullsToUndefined = obj => Object.entries(obj).reduce(
  (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
  {},
)

export default {
  nullsToUndefined,
}

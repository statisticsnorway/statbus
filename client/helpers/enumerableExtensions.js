const defaultKeySelector = v => v

export const groupByToMap = (arr = [], keySelector = defaultKeySelector) => {
  const lookup = new Map()
  arr.forEach((item, ix) => {
    const key = keySelector(item, ix)
    const group = lookup.get(key)
    if (group === undefined) {
      lookup.set(key, [item])
    } else {
      group.push(item)
    }
  })
  return lookup
}

const defaultResultMapper = (key, value) => ({ key, value })

export const mapToArray = (map, resultMapper = defaultResultMapper) =>
  [...map.entries()].map(([key, value]) => resultMapper(key, value))

export const groupByToArray = (
  arr = [],
  keySelector = defaultKeySelector,
  resultMapper = defaultResultMapper,
) => mapToArray(groupByToMap(arr, keySelector), resultMapper)

import * as R from 'ramda'

export const groupByToMap = (arr = [], keySelector = R.identity) => {
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

const defaultObjectMapper = (key, value) => ({ key, value })

export const mapToArray = (map, resultMapper = defaultObjectMapper) =>
  [...map].map(([key, value]) => resultMapper(key, value))

export const groupByToArray = (
  arr = [],
  keySelector = R.identity,
  resultMapper = defaultObjectMapper,
) => mapToArray(groupByToMap(arr, keySelector), resultMapper)

export const distinctBy = (argArr, selector) =>
  argArr.filter((elem, pos, arr) => {
    const item = arr.find(x => selector(elem) === selector(x))
    return arr.indexOf(item) === pos
  })

export const pairsToOptions = (pairs, transformValue = R.identity) =>
  [...pairs.entries()].map(pair => ({
    value: pair[0],
    text: transformValue(pair[1]),
  }))

export const oneOf = xs => x => xs.includes(x)

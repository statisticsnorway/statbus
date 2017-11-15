import { pipe } from 'ramda'

const shouldPropBeMapped = ([, value]) => typeof value === 'number' || value
const addStartPrefix = str => (str.length > 0 ? `?${str}` : str)

const toQueryParams = (obj, prefix = '') =>
  Object.entries(obj)
    .filter(shouldPropBeMapped)
    .reduce((res, [key, value], i, arr) => {
      const pair =
        typeof value === 'object'
          ? toQueryParams(value, `${prefix}${key}.`)
          : `${encodeURIComponent(`${prefix}${key}`)}=${encodeURIComponent(value)}`
      return `${res}${pair}${i !== arr.length - 1 ? '&' : ''}`
    }, '')

export default pipe(toQueryParams, addStartPrefix)

import * as R from 'ramda'

const shouldPropBeMapped = value => typeof value === 'number' || value
const addStartPrefix = str => (str.length > 0 ? `?${str}` : str)

const toQueryParams = (raw, prefix = '', hideKey = false) =>
  Object.entries(raw).reduce((result, [key, value], i, arr) => {
    if (!shouldPropBeMapped(value)) return result
    const pair = Array.isArray(value)
      ? toQueryParams(value, `${prefix}${key}`, true)
      : typeof value === 'object'
        ? toQueryParams(value, `${prefix}${key}.`)
        : `${encodeURIComponent(`${prefix}${hideKey ? '' : key}`)}=${encodeURIComponent(value)}`
    return `${result}${pair}${i !== arr.length - 1 ? '&' : ''}`
  }, '')

export default R.pipe(toQueryParams, addStartPrefix)

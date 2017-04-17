const shouldPropBeMapped = prop => typeof (prop.value) === 'number' || prop.value

const toQueryParams = (obj, prefix) => (
  Object.entries(obj)
    .map(([key, value]) => ({ key, value }))
    .filter(shouldPropBeMapped)
    .reduce(
      (res, x, i, arr) => {
        const pair = typeof (x.value) === 'object'
          ? toQueryParams(x.value, `${prefix}${x.key}.`)
          : `${encodeURIComponent(`${prefix}${x.key}`)}=${encodeURIComponent(x.value)}`
        return `${res}${pair}${i !== arr.length - 1 ? '&' : ''}`
      },
      '',
    )
)

export default queryParams => toQueryParams(queryParams, '')

const shouldPropBeMapped = prop => typeof (prop.value) === 'number' || prop.value

export default queryParams =>
  Object.entries(queryParams)
    .map(([key, value]) => ({ key, value }))
    .filter(shouldPropBeMapped)
    .reduce(
      (res, x, i, arr) => `${res}${x.key}=${x.value}${i !== arr.length - 1 ? '&' : ''}`,
      '',
    )

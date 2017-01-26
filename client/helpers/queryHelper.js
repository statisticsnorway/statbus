const shouldPropBeMapped = prop => typeof (prop.value) === 'number' || prop.value

export default queryParams =>
  Object.keys(queryParams)
    .map(k => ({ key: k, value: queryParams[k] }))
    .filter(shouldPropBeMapped)
    .reduce(
      (res, x, i, arr) => `${res}${x.key}=${x.value}${i !== arr.length - 1 ? '&' : ''}`,
      '',
    )

export const cloneFormObj = formData =>
  Object.entries(formData)
    .reduce((res, [k, v]) => ({ ...res, [k]: v === '' ? null : v }), {})


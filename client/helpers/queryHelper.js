const shouldPropBeMapped = prop => typeof (prop.value) === 'number' || prop.value

export const queryObjToString = queryParams => Object.keys(queryParams)
      .map(k => ({ key: k, value: queryParams[k] }))
      .filter(x => shouldPropBeMapped(x))
      .reduce((res, x, i, arr) =>
      `${res}${x.key}=${x.value}${i !== arr.length - 1 ? '&' : ''}`, '')

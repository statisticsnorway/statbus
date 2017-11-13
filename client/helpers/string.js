export function toCamelCase(str) {
  return str === undefined || str.length <= 1 ? str : str.charAt(0).toLowerCase() + str.slice(1)
}

export function toPascalCase(str) {
  return str === undefined || str.length <= 1 ? str : str.charAt(0).toUpperCase() + str.slice(1)
}

export function createJsonReviver(transform) {
  // eslint-disable-next-line consistent-return
  return function jsonReviver(key, value) {
    if (key) this[transform(key)] = value
    else return value
  }
}

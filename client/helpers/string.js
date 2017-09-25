export const toCamelCase = str => str === undefined || str.length <= 1
  ? str
  : str.charAt(0).toLowerCase() + str.slice(1)

export const toPascalCase = str => str === undefined || str.length <= 1
  ? str
  : str.charAt(0).toUpperCase() + str.slice(1)

export function createJsonReviver(key, value) {
  // eslint-disable-next-line consistent-return
  return function jsonReviver(transform) {
    if (key) this[transform(key)] = value
    else return value
  }
}

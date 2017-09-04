export const camelize = str => str === undefined || str.length <= 1
  ? str
  : str.charAt(0).toLowerCase() + str.slice(1)

// eslint-disable-next-line consistent-return
export function jsonReviver(key, value) {
  if (key) this[camelize(key)] = value
  else return value
}

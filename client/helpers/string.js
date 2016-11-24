export const pascalCaseToCamelCase = str => str === undefined || str.length <= 1
  ? str
  : str.charAt(0).toLowerCase() + str.slice(1)

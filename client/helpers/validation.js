import { shape } from 'prop-types'
import { pipe, anyPass, isNil, isEmpty, any, values, not } from 'ramda'

export const nullsToUndefined = obj =>
  Object.entries(obj).reduce(
    (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
    {},
  )

export const hasValue = pipe(anyPass([isNil, isEmpty]), not)

export const hasValues = pipe(values, any(hasValue))

export const ensureArray = value => (Array.isArray(value) ? value : value ? [value] : [])

export const shapeOf = fields => propType =>
  shape(fields.reduce((acc, curr) => ({ ...acc, [curr]: propType }), {}))

// eslint-disable-next-line consistent-return
export const createPropType = mapPropsToPropTypes => (props, propName, componentName, ...rest) => {
  const propType = mapPropsToPropTypes(props, propName, componentName)
  const error = propType(props, propName, componentName, ...rest)
  if (error) return error // WIP - not sure what exactly, seems to be working fine...
}

import { shape } from 'prop-types'
import { pipe, anyPass, isNil, isEmpty, any, values, not } from 'ramda'
import { isDateInThePast } from './dateHelper'

export const nullsToUndefined = obj =>
  Object.entries(obj).reduce(
    (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
    {},
  )

export const hasValue = pipe(anyPass([isNil, isEmpty]), not)

export const getCorrectQuery = (formData) => {
  const keys = Object.keys(formData)
  return keys.reduce((acc, key) => {
    if (isEmpty(formData[key])) {
      return acc
    }
    acc[key] = formData[key]
    return acc
  }, {})
}

export const filterPredicateErrors = errors =>
  errors.filter(x => hasValue(x)).reduce((acc, el) => {
    if (!acc.includes(el.value)) {
      acc.push(el.value)
      return acc
    }
    return acc
  }, [])

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

export const hasValueAndInThePast = x => hasValue(x) && isDateInThePast(x)

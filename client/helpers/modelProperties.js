import { getMandatoryFields } from 'helpers/config'
import { toPascalCase } from 'helpers/string'

export const castEmptyOrNull = x => (x === '' ? null : x === null ? undefined : x)

export const createModel = (dataAccess, properties) =>
  Object.entries(properties).reduce(
    (acc, [, v]) => ({
      ...acc,
      [v.name]: castEmptyOrNull(v.value),
    }),
    { dataAccess },
  )

export const updateProperties = (model, properties) =>
  properties.map(p => (model[p.name] === undefined ? p : { ...p, value: model[p.name] }))

export const createFieldsMeta = (type, properties) => {
  const mandatoryFields = getMandatoryFields(type)
  return properties.reduce(
    (acc, cur) => ({
      ...acc,
      [cur.name]:
        !cur.isRequired && mandatoryFields.includes(toPascalCase(cur.name))
          ? { ...cur, isRequired: true }
          : cur,
    }),
    {},
  )
}

export const createValues = (dataAccess, properties) =>
  Object.entries(properties).reduce(
    (acc, [, v]) => ({
      ...acc,
      [v.name]: castEmptyOrNull(v.value),
    }),
    {},
  )

export const updateValuesFrom = source => target =>
  Object.keys(target).reduce((acc, key) => ({ ...acc, [key]: source[key] }), target)

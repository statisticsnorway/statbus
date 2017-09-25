import config from 'helpers/config'
import { statUnitTypes } from 'helpers/enums'
import { toCamelCase } from 'helpers/string'

export const castEmptyOrNull = x =>
  x === ''
    ? null
    : x === null
      ? undefined
      : x

export const createModel = (dataAccess, properties) =>
  Object.entries(properties)
    .reduce(
      (acc, [, v]) => ({
        ...acc,
        [v.name]: castEmptyOrNull(v.value),
      }),
      { dataAccess },
    )

export const updateProperties = (model, properties) =>
  properties.map(
    p => model[p.name] === undefined
      ? p
      : { ...p, value: model[p.name] },
  )

export const createFieldsMeta = (type, properties) => {
  const mandatoryFields = Object.entries({
    ...config.mandatoryFields.StatUnit,
    ...config.mandatoryFields[statUnitTypes.get(Number(type))],
  }).reduce(
    (acc, [prop, isRequired]) => isRequired
      ? [...acc, toCamelCase(prop)]
      : acc,
    [],
  )
  return properties.reduce(
    (acc, cur) => ({
      ...acc,
      [cur.name]: !cur.isRequired && mandatoryFields.includes(cur.name)
        ? { ...cur, isRequired: true }
        : cur,
    }),
    {},
  )
}

export const createValues = (dataAccess, properties) =>
  Object.entries(properties)
    .reduce(
    (acc, [, v]) => ({
      ...acc,
      [v.name]: castEmptyOrNull(v.value),
    }),
    { },
  )

import { array, number, object, string } from 'yup'
import { map } from 'ramda'

import { getMandatoryFields } from '/helpers/config'
import * as enums from '/helpers/enums'
import { toCamelCase } from '/helpers/string'

export const defaults = {
  name: '',
  description: '',
  allowedOperations: 1,
  attributesToCheck: [],
  priority: 1,
  statUnitType: 2,
  variablesMapping: [],
  csvDelimiter: ',',
  csvSkipCount: 0,
  dataSourceUploadType: 1,
}

export const getMandatoryFieldsForActivityUpload = () => [
  'StatId',
  'Activities.ActivityType',
  'Activities.ActivityYear',
  'Activities.Employees',
  'Activities.Turnover',
  'Activities.ActivityCategory.Code',
]

export const getFieldsForActivityUpload = () => [
  'StatId',
  'Activities.ActivityCategory.Code',
  'Activities.ActivityCategory.Name',
  'Activities.ActivityYear',
  'Activities.Employees',
  'Activities.Turnover',
  'Activities.ActivityType',
]

export const getFieldsForUpdate = () => ['StatId', 'TaxRegId', 'ExternalId']

function getColsWithPoints(cols, fieldName) {
  return cols.filter(x => x.split('.').length > 1 && x.split('.')[0] === fieldName)
}

function filterNameAndCode(value, isEqual) {
  const lastVal = value.split('.').pop()
  if (isEqual) {
    return lastVal.includes('Name') || lastVal.includes('Code')
  }
  return lastVal.includes('Name') && lastVal.includes('Code')
}

export function tryFieldIsRequired(cols, field, variablesMapping) {
  const var1 = cols.includes(field) && !variablesMapping.map(([, prop]) => prop).includes(field)
  const var2 =
    getColsWithPoints(cols, field).length > 0 &&
    getColsWithPoints(cols, field)
      .filter(x => filterNameAndCode(x, false))
      .filter(s =>
        !variablesMapping
          .map(([, vari]) => vari)
          .filter(x => filterNameAndCode(x, false))
          .includes(s)).length > 0
  const var3 =
    getColsWithPoints(cols, field).length > 0 &&
    getColsWithPoints(cols, field)
      .filter(x => filterNameAndCode(x, true))
      .filter(s =>
        !variablesMapping
          .map(([, vari]) => vari)
          .filter(x => x.split('.')[0] === field && filterNameAndCode(x, true))
          .includes(s)).length > 1

  return var1 || var2 || var3
}

export function tryFieldIsRequiredForUpdate(variablesMapping) {
  const variablesForCheck = getFieldsForUpdate()
  let isValidUpdate = false

  variablesForCheck.forEach((field) => {
    // eslint-disable-next-line array-callback-return
    variablesMapping.some((el) => {
      if (el[1] === field) {
        isValidUpdate = true
      }
    })
  })

  return isValidUpdate
}

function testStatUnitMappings(context, columns, isUpdate) {
  const cols = columns[
    toCamelCase(enums.statUnitTypes.get(Number(context.parent.statUnitType)))
  ].map(col => col.name)

  const mandatoryFields = getMandatoryFields(context.parent.statUnitType)

  const message = mandatoryFields
    .filter(field => tryFieldIsRequired(cols, field, context.parent.variablesMapping))
    .map(field => `${field}IsRequired`)

  if (isUpdate) {
    return tryFieldIsRequiredForUpdate(context.parent.variablesMapping)
      ? true
      : {
        ...context.createError('', 'variablesMapping'),
        message: 'One of these fields (StatId/TaxRegId/ExternalId) -  should be filled',
      }
  }
  return message.length > 0 ? { ...context.createError('', 'variablesMapping'), message } : true
}

function testActivityMappings(context) {
  const message = getMandatoryFieldsForActivityUpload()
    .filter(field => context.parent.variablesMapping.every(([, prop]) => prop !== field))
    .map(field => `${field}IsRequired`.replace('.', ''))
  return message.length > 0 ? { ...context.createError('', 'variablesMapping'), message } : true
}

export const createSchema = columns =>
  object({
    name: string()
      .required('NameIsRequired')
      .trim()
      .default(defaults.name),
    description: string().default(defaults.description),
    allowedOperations: number()
      .required()
      .default(defaults.allowedOperations),
    attributesToCheck: array(string()).default(defaults.attributesToCheck),
    priority: number()
      .required()
      .default(defaults.priority),
    statUnitType: number()
      .required()
      .default(defaults.statUnitType),
    variablesMapping: array(array(string()))
      .default(defaults.variablesMapping)
      .test('mandatory-fields-covered', '', function testWrap() {
        const isStatUnitUpload = this.parent.dataSourceUploadType === 1
        const isUpdate = this.parent.allowedOperations === 2
        return isStatUnitUpload
          ? testStatUnitMappings(this, columns, isUpdate)
          : testActivityMappings(this)
      }),
    csvDelimiter: string()
      .required()
      .default(defaults.csvDelimiter),
    csvSkipCount: number()
      .default(defaults.csvSkipCount)
      .required(),
  })

const unmap = map(([value, text]) => ({ value, text }))

export const meta = new Map([
  ['name', { type: 'text', label: 'Name' }],
  ['description', { type: 'text', label: 'Description' }],
  [
    'allowedOperations',
    {
      label: 'AllowedOperations',
      options: unmap([...enums.dataSourceOperations]),
    },
  ],
  ['priority', { label: 'Priority', options: unmap([...enums.dataSourcePriorities]) }],
  [
    'statUnitType',
    {
      label: 'StatUnit',
      options: unmap([...enums.statUnitTypes]).filter(x => x.value < 4),
    },
  ],
  ['csvDelimiter', { type: 'text', label: 'CsvDelimiter' }],
  ['csvSkipCount', { label: 'CsvSkipCount' }],
  [
    'dataSourceUploadType',
    {
      label: 'DataSourceUploadType',
      options: unmap([...enums.dataSourceUploadTypes]),
    },
  ],
])

const stringifyMapping = pairs => pairs.map(pair => `${pair[0]}-${pair[1]}`).join(',')

export const transformMapping = ({ variablesMapping, ...rest }) => ({
  ...rest,
  variablesMapping: stringifyMapping(variablesMapping),
})

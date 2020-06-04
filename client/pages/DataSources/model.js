import { array, number, object, string } from 'yup'
import { map } from 'ramda'

import { getMandatoryFields } from 'helpers/config'
import * as enums from 'helpers/enums'
import { toCamelCase } from 'helpers/string'

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

function testStatUnitMappings(context, columns) {
  const cols = columns[
    toCamelCase(enums.statUnitTypes.get(Number(context.parent.statUnitType)))
  ].map(col => col.name)
  const message = getMandatoryFields(context.parent.statUnitType)
    .filter(field =>
      cols.includes(field) && context.parent.variablesMapping.every(([, prop]) => prop !== field))
    .map(field => `${field}IsRequired`)
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
        return isStatUnitUpload ? testStatUnitMappings(this, columns) : testActivityMappings(this)
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

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
}

export const createSchema = columns =>
  object({
    name: string()
      .required()
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
      .test('mandatory-fields-covered', '', function testFn(mapping) {
        const cols = columns[
          toCamelCase(enums.statUnitTypes.get(Number(this.parent.statUnitType)))
        ].map(col => col.name)
        const message = getMandatoryFields(this.parent.statUnitType)
          .filter(field => cols.includes(field) && mapping.every(([, prop]) => prop !== field))
          .map(field => `${field}IsRequired`)
        return message.length > 0 ? { ...this.createError('', 'variablesMapping'), message } : true
      }),
    csvDelimiter: string()
      .required()
      .default(defaults.csvDelimiter),
    csvSkipCount: number()
      .positive()
      .default(defaults.csvSkipCount)
      .required(),
  })

const unmap = map(([value, text]) => ({ value, text }))

export const meta = new Map([
  ['name', { type: 'text', label: 'Name' }],
  ['description', { type: 'text', label: 'Description' }],
  [
    'allowedOperations',
    { label: 'AllowedOperations', options: unmap([...enums.dataSourceOperations]) },
  ],
  ['priority', { label: 'Priority', options: unmap([...enums.dataSourcePriorities]) }],
  [
    'statUnitType',
    { label: 'StatUnit', options: unmap([...enums.statUnitTypes]).filter(x => x.value < 4) },
  ],
  ['csvDelimiter', { type: 'text', label: 'CsvDelimiter' }],
  ['csvSkipCount', { label: 'CsvSkipCount' }],
])

const stringifyMapping = pairs => pairs.map(pair => `${pair[0]}-${pair[1]}`).join(',')

export const transformMapping = ({ variablesMapping, ...rest }) => ({
  ...rest,
  variablesMapping: stringifyMapping(variablesMapping),
})

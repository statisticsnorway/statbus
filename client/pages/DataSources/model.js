import { array, number, object, string } from 'yup'
import { map } from 'ramda'

import * as enums from 'helpers/enums'

export const schema = object({
  name: string().required().trim().max(20).default(''),
  description: string().max(30).default(''),
  allowedOperations: number().required().default(1),
  attributesToCheck: array(string()).default([]),
  priority: number().required().default(1),
  statUnitType: number().required().default(1),
  variablesMapping: array(array(string())).required().default([]),
})

const unmap = map(([value, text]) => ({ value, text }))

export const meta = new Map([
  ['name', {
    type: 'text',
    label: 'Name',
  }],
  ['description', {
    type: 'text',
    label: 'Description',
  }],
  ['allowedOperations', {
    type: 'select?',
    label: 'AllowedOperations',
    options: unmap([...enums.dataSourceOperations]),
  }],
  ['priority', {
    type: 'select?',
    label: 'Priority',
    options: unmap([...enums.dataSourcePriorities]),
  }],
  ['statUnitType', {
    type: 'select?',
    label: 'StatUnit',
    options: unmap([...enums.statUnitTypes]).filter(x => x.value < 4),
  }],
])

const stringifyMapping = pairs => pairs.map(pair => `${pair[0]}-${pair[1]}`).join(',')

export const transformMapping = ({ variablesMapping, ...rest }) =>
  ({ ...rest, variablesMapping: stringifyMapping(variablesMapping) })

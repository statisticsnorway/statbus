import React from 'react'

import CheckField from './fields/CheckField'
import DateField from './fields/DateField'
import TextField from './fields/TextField'
import SelectField from './fields/SelectField'

const propertyTypeMap = new Map([
  [0, 'Boolean'],
  [1, 'DateTime'],
  [2, 'Float'],
  [3, 'Integer'],
  [4, 'MultiReference'],
  [5, 'Reference'],
  [6, 'String'],
])

const mapPropertyToComponent = (item, errors) => {
  switch (propertyTypeMap.get(item.selector)) {
    case 'Boolean':
      return <CheckField item={item} errors={errors} />
    case 'DateTime':
      return <DateField item={item} errors={errors} />
    case 'Float':
    case 'Integer':
    case 'String':
      return <TextField item={item} errors={errors} />
    case 'MultiReference':
      return <SelectField item={item} errors={errors} multiselect />
    case 'Reference':
      return <SelectField item={item} errors={errors} />
    default:
      throw new Error(item)
  }
}

export default mapPropertyToComponent

import React from 'react'
import CheckField from 'components/CheckField'
import DateField from 'components/DateField'
import TextField from 'components/TextField'
import SelectField from 'components/SelectField'

const typeMap = new Map([
  [0, 'Boolean'],
  [1, 'DateTime'],
  [2, 'Float'],
  [3, 'Integer'],
  [4, 'MultiReference'],
  [5, 'Reference'],
  [6, 'String'],
])

const mapPropertyToComponent = (item, errors) => {
  switch (typeMap.get(item.selector)) {
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

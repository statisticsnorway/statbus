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

const mapPropertyToComponent = (item, errors = [], onChange) => {
  switch (propertyTypeMap.get(item.selector)) {
    case 'Boolean':
      return (
        <CheckField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
        />
      )
    case 'DateTime':
      return (
        <DateField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          errors={errors}
        />
      )
    case 'Float':
    case 'Integer':
    case 'String':
      return (
        <TextField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          errors={errors}
        />
      )
    case 'MultiReference':
      return (
        <SelectField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          errors={errors}
          required={item.isRequired}
          multiselect
        />
      )
    case 'Reference':
      return (
        <SelectField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          errors={errors}
          required={item.isRequired}
        />
      )
    default:
      throw new Error(item)
  }
}

export default mapPropertyToComponent

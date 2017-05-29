import React from 'react'

import CheckField from './fields/CheckField'
import DateField from './fields/DateField'
import NumberField from './fields/NumberField'
import TextField from './fields/TextField'
import SelectField from './fields/SelectField'
import ActivitiesGrid from './fields/Activities'
import Address from './fields/Address'
import Country from './fields/Country'

export const propertyTypeMap = new Map([
  [0, 'Boolean'],
  [1, 'DateTime'],
  [2, 'Float'],
  [3, 'Integer'],
  [4, 'MultiReference'],
  [5, 'Reference'],
  [6, 'String'],
  [7, 'Activities'],
  [8, 'Addresses'],
  [9, 'Countries'],
])

export default (item, errors = [], onChange, localize) => {
  switch (propertyTypeMap.get(item.selector)) {
    case 'Boolean':
      return (
        <CheckField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          localize={localize}
          errors={errors}
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
          localize={localize}
          errors={errors}
        />
      )
    case 'Float':
    case 'Integer':
      return (
        <NumberField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          required={item.isRequired}
          localize={localize}
          errors={errors}
        />
      )
    case 'String':
      return (
        <TextField
          key={item.name}
          name={item.name}
          value={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          required={item.isRequired}
          localize={localize}
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
          lookup={item.lookup}
          required={item.isRequired}
          multiselect
          localize={localize}
          errors={errors}
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
          lookup={item.lookup}
          required={item.isRequired}
          localize={localize}
          errors={errors}
        />
      )
    case 'Activities':
      return (
        <ActivitiesGrid
          key={item.name}
          name={item.name}
          data={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          localize={localize}
          errors={errors}
        />
      )
    case 'Addresses':
      return (
        <Address
          key={item.name}
          name={item.name}
          data={item.value}
          onChange={onChange}
          localize={localize}
          errors={errors}
        />
      )
    case 'Countries':
      return (
        <Country
          key={item.name}
          name={item.name}
          data={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          localize={localize}
          errors={errors}
        />
      )
    default:
      throw new Error(item)
  }
}

import React from 'react'

import { statUnitFormFieldTypes } from 'helpers/enums'
import CheckField from './fields/CheckField'
import DateField from './fields/DateField'
import NumberField from './fields/NumberField'
import TextField from './fields/TextField'
import SelectField from './fields/SelectField'
import ActivitiesGrid from './fields/Activities'
import PersonsGrid from './fields/Persons'
import Address from './fields/Address'
import SearchLookup from './fields/SearchLookup'

export default (item, errors = [], onChange, localize) => {
  switch (statUnitFormFieldTypes.get(item.selector)) {
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
          required={item.isRequired}
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
          required={item.isRequired}
          labelKey={item.localizeKey}
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
          required={item.isRequired}
          labelKey={item.localizeKey}
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
          required={item.isRequired}
          lookup={item.lookup}
          labelKey={item.localizeKey}
          localize={localize}
          errors={errors}
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
          required={item.isRequired}
          labelKey={item.localizeKey}
          lookup={item.lookup}
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
    case 'Persons':
      return (
        <PersonsGrid
          key={item.name}
          name={item.name}
          data={item.value}
          onChange={onChange}
          labelKey={item.localizeKey}
          localize={localize}
          errors={errors}
        />
      )
    case 'SearchComponent':
      return (
        <SearchLookup
          key={item.name}
          name={item.name}
          value={item.value}
          required={item.isRequired}
          onChange={onChange}
          localize={localize}
          errors={errors}
        />
      )
    default:
      throw new Error(item)
  }
}

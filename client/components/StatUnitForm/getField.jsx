import React from 'react'

import { statUnitFormFieldTypes } from 'helpers/enums'
import CheckField from './fields/CheckField'
import DateTimeField from './fields/DateTimeField'
import NumberField from './fields/NumberField'
import TextField from './fields/TextField'
import SelectField from './fields/SelectField'
import ActivitiesField from './fields/ActivitiesField'
import PersonsField from './fields/PersonsField'
import AddressField from './fields/AddressField'
import SearchField from './fields/SearchField'

// TODO: check onChange handler and other props match
export default (type, props) => {
  switch (statUnitFormFieldTypes.get(type)) {
    case 'Boolean':
      return <CheckField {...props} />
    case 'DateTime':
      return <DateTimeField {...props} />
    case 'Float':
    case 'Integer':
      return <NumberField {...props} />
    case 'String':
      return <TextField {...props} />
    case 'MultiReference':
      return <SelectField {...props} multiselect />
    case 'Reference':
      return <SelectField {...props} />
    case 'Activities':
      return <ActivitiesField {...props} />
    case 'Addresses':
      return <AddressField {...props} />
    case 'Persons':
      return <PersonsField {...props} />
    case 'SearchComponent':
      return <SearchField {...props} />
    default:
      throw new Error({ type, ...props })
  }
}

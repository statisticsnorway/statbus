import React from 'react'

import { statUnitFormFieldTypes } from 'helpers/enums'
import CheckField from 'components/StatUnitForm/fields/CheckField'
import DateField from 'components/StatUnitForm/fields/DateField'
import NumberField from 'components/StatUnitForm/fields/NumberField'
import TextField from 'components/StatUnitForm/fields/TextField'
import SelectField from 'components/StatUnitForm/fields/SelectField'
import ActivitiesGrid from 'components/StatUnitForm/fields/Activities'
import PersonsGrid from 'components/StatUnitForm/fields/Persons'
import Address from 'components/StatUnitForm/fields/Address'
import SearchLookup from 'components/StatUnitForm/fields/SearchLookup'

export default (type, ...props) => {
  switch (statUnitFormFieldTypes.get(type)) {
    case 'Boolean':
      return <CheckField {...props} />
    case 'DateTime':
      return <DateField {...props} />
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
      return <ActivitiesGrid {...props} />
    case 'Addresses':
      return <Address {...props} />
    case 'Persons':
      return <PersonsGrid {...props} />
    case 'SearchComponent':
      return <SearchLookup {...props} />
    default:
      throw new Error(props)
  }
}

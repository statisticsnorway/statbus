import React from 'react'

import { statUnitFormFieldTypes } from 'helpers/enums'
import Check from './fields/Check'
import DateTime from './fields/DateTime'
import Numeric from './fields/Numeric'
import Text from './fields/Text'
import Select from './fields/Select'
import Activities from './fields/Activities'
import Persons from './fields/Persons'
import Address from './fields/Address'
import Search from './fields/Search'

export default (type, ...props) => {
  switch (statUnitFormFieldTypes.get(type)) {
    case 'Boolean':
      return <Check {...props} />
    case 'DateTime':
      return <DateTime {...props} />
    case 'Float':
    case 'Integer':
      return <Numeric {...props} />
    case 'String':
      return <Text {...props} />
    case 'MultiReference':
      return <Select {...props} multiselect />
    case 'Reference':
      return <Select {...props} />
    case 'Activities':
      return <Activities {...props} />
    case 'Addresses':
      return <Address {...props} />
    case 'Persons':
      return <Persons {...props} />
    case 'SearchComponent':
      return <Search {...props} />
    default:
      throw new Error(props)
  }
}

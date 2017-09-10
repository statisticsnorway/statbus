import React from 'react'
import PropTypes from 'prop-types'

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
import withDebounce from './withDebounce'

const DebouncedCheckField = withDebounce(CheckField)
const DebouncedDateTimeField = withDebounce(DateTimeField)
const DebouncedNumberField = withDebounce(NumberField)
const DebouncedTextField = withDebounce(TextField)

const Field = ({ fieldType, ...props }) => {
  switch (statUnitFormFieldTypes.get(fieldType)) {
    case 'Boolean':
      return <DebouncedCheckField {...props} />
    case 'DateTime':
      return <DebouncedDateTimeField {...props} />
    case 'Float':
    case 'Integer':
      return <DebouncedNumberField {...props} />
    case 'String':
      return <DebouncedTextField {...props} />
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
      return null
  }
}

const { oneOf } = PropTypes
Field.propTypes = {
  fieldType: oneOf([...statUnitFormFieldTypes.keys]).isRequired,
}

export default Field

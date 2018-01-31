import React from 'react'
import PropTypes from 'prop-types'

import { statUnitFormFieldTypes } from 'helpers/enums'
import CheckField from 'components/fields/CheckField'
import DateTimeField from 'components/fields/DateTimeField'
import NumberField from 'components/fields/NumberField'
import TextField from 'components/fields/TextField'
import SelectField from 'components/fields/SelectField'
import ActivitiesField from 'components/fields/ActivitiesField'
import PersonsField from 'components/fields/PersonsField'
import AddressField from 'components/fields/AddressField'
import SearchField from 'components/fields/SearchField'
import withDebounce from 'components/fields/withDebounce'

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
      return <DebouncedTextField {...props} highlighted={props.validationUrl !== null} />
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

const { oneOf, string } = PropTypes
Field.propTypes = {
  fieldType: oneOf([...statUnitFormFieldTypes.keys]).isRequired,
  validationUrl: string,
}

Field.defaultProps = {
  validationUrl: null,
}

export default Field

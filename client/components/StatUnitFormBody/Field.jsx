import React from 'react'
import PropTypes from 'prop-types'

import { statUnitFormFieldTypes } from 'helpers/enums'
import handlerFor from 'helpers/handleSetFieldValue'
import {
  CheckField,
  DateTimeField,
  NumberField,
  TextField,
  SelectField,
  ActivitiesField,
  PersonsField,
  AddressField,
  SearchField,
  withDebounce,
} from 'components/fields'

const DebouncedCheckField = withDebounce(CheckField)
const DebouncedDateTimeField = withDebounce(DateTimeField)
const DebouncedNumberField = withDebounce(NumberField)
const DebouncedTextField = withDebounce(TextField)

const Field = ({ fieldType, setFieldValue, validationUrl, ...props }) => {
  const onChange = handlerFor(setFieldValue)
  switch (statUnitFormFieldTypes.get(fieldType)) {
    case 'Boolean':
      return <DebouncedCheckField {...props} onChange={onChange} />
    case 'DateTime':
      return <DebouncedDateTimeField {...props} onChange={onChange} />
    case 'Float':
    case 'Integer':
      return <DebouncedNumberField {...props} onChange={onChange} />
    case 'String':
      return (
        <DebouncedTextField {...props} onChange={onChange} highlighted={validationUrl !== null} />
      )
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

import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import { isNil } from 'ramda'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

const asDate = x => (isNil(x) ? x : toUtc(x))

const DateTimeField = ({
  id: ambiguousId,
  name,
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  required,
  errors: errorKeys,
  setFieldValue,
  localize,
  ...restProps
}) => {
  const hasErrors = touched && hasValue(errorKeys)
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const id = ambiguousId != null ? ambiguousId : name
  const props = {
    ...restProps,
    id,
    name,
    value,
    title,
    dateFormat,
    required,
    as: DatePicker,
    selected: isNil(value) ? null : getDate(value),
    error: error || hasErrors,
    onChange: nextValue => setFieldValue(name, asDate(nextValue)),
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    className: 'ui input',
  }
  return (
    <div className={`field datepicker${required ? ' required' : ''}${hasErrors ? ' error' : ''}`}>
      <label htmlFor={id}>{label}</label>
      <Form.Input {...props} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

DateTimeField.propTypes = {
  id: string,
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: string,
  required: bool,
  touched: bool.isRequired,
  error: bool,
  errors: arrayOf(string),
  setFieldValue: func.isRequired,
  localize: func.isRequired,
}

DateTimeField.defaultProps = {
  id: undefined,
  title: undefined,
  placeholder: undefined,
  value: null,
  required: false,
  error: false,
  errors: [],
}

export default DateTimeField

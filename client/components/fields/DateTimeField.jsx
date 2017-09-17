import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import { isNil } from 'ramda'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

const asDate = x => isNil(x) ? x : toUtc(x)

const DateTimeField = ({
  name, value, label: labelKey, title: titleKey,
  placeholder: placeholderKey, touched, required, errors: errorKeys, disabled,
  setFieldValue, onBlur, localize,
}) => {
  const handleChange = (nextValue) => {
    setFieldValue(name, asDate(nextValue))
  }
  const hasErrors = touched && hasValue(errorKeys)
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  return (
    <div className="field datepicker">
      <label htmlFor={name}>{label}</label>
      <Form.Input
        as={DatePicker}
        id={name}
        name={name}
        title={title}
        placeholderText={placeholder}
        selected={isNil(value)
          ? null
          : getDate(value)}
        value={value}
        dateFormat={dateFormat}
        className="ui input"
        onChange={handleChange}
        onBlur={onBlur}
        required={required}
        error={hasErrors}
        disabled={disabled}
      />
      {hasErrors &&
        <Message title={label} list={errorKeys.map(localize)} error />}
    </div>
  )
}

DateTimeField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: string,
  required: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  disabled: bool,
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

DateTimeField.defaultProps = {
  title: undefined,
  placeholder: undefined,
  value: null,
  required: false,
  errors: [],
  disabled: false,
  onBlur: _ => _,
}

export default DateTimeField

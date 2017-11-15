import React from 'react'
import { bool, arrayOf, func, string, oneOfType, number } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import { isNil } from 'ramda'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

const asDate = x => (isNil(x) ? x : toUtc(x))

const DateTimeField = ({
  name,
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  required,
  errors: errorKeys,
  disabled,
  inline,
  width,
  setFieldValue,
  onBlur,
  onKeyDown,
  localize,
}) => {
  const handleChange = (nextValue) => {
    setFieldValue(name, asDate(nextValue))
  }
  const hasErrors = touched && hasValue(errorKeys)
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  const className = `field datepicker${required ? ' required' : ''}${hasErrors ? ' error' : ''}`
  return (
    <div className={className}>
      <label htmlFor={name}>{label}</label>
      <Form.Input
        as={DatePicker}
        id={name}
        name={name}
        title={title}
        placeholderText={placeholder}
        selected={isNil(value) ? null : getDate(value)}
        value={value}
        dateFormat={dateFormat}
        className="ui input"
        onChange={handleChange}
        onBlur={onBlur}
        onKeyDown={onKeyDown}
        disabled={disabled}
        inline={inline}
        width={width}
      />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
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
  inline: bool,
  width: oneOfType([number, string]),
  setFieldValue: func.isRequired,
  onBlur: func,
  onKeyDown: func,
  localize: func.isRequired,
}

DateTimeField.defaultProps = {
  title: undefined,
  placeholder: undefined,
  value: null,
  required: false,
  errors: [],
  disabled: false,
  inline: false,
  width: undefined,
  onBlur: _ => _,
  onKeyDown: undefined,
}

export default DateTimeField

import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'

const asDate = x => x === null ? null : toUtc(x)

const DateTimeField = ({
  name, value, label: labelKey, title, placeholder,
  touched, required, errors,
  setFieldValue, onBlur, localize,
}) => {
  const handleChange = (_, { value: nextValue }) => {
    setFieldValue(name, asDate(nextValue))
  }
  const hasErrors = touched && errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field datepicker">
      <label htmlFor={name}>{label}</label>
      <Form.Input
        as={DatePicker}
        id={name}
        name={name}
        title={title || label}
        placeholder={placeholder}
        selected={value === undefined || value === null
          ? null
          : getDate(value)}
        value={value}
        dateFormat={dateFormat}
        className="ui input"
        onChange={handleChange}
        onBlur={onBlur}
        required={required}
        error={hasErrors}
      />
      {hasErrors &&
        <Message title={label} list={errors.map(localize)} error />}
    </div>
  )
}

DateTimeField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: string.isRequired,
  required: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

DateTimeField.defaultProps = {
  title: undefined,
  placeholder: undefined,
  required: false,
  errors: [],
  onBlur: _ => _,
}

export default DateTimeField

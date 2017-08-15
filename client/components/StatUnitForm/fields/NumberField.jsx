import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'
import { equals, anyPass } from 'ramda'

const isBlank = anyPass([equals(undefined), equals(''), equals(null)])

const NumberField = ({
  name, value, label: labelKey, title, placeholder,
  touched, required, errors,
  setFieldValue, onBlur, localize,
}) => {
  const handleChange = (_, { value: nextValue }) => {
    setFieldValue(name, isBlank(nextValue) ? null : nextValue)
  }
  const hasErrors = touched && errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <Form.Input
        type="number"
        name={name}
        label={label}
        title={title || label}
        placeholder={placeholder}
        value={value}
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

NumberField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: oneOfType([string, number]),
  required: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

NumberField.defaultProps = {
  value: '',
  title: undefined,
  placeholder: undefined,
  required: false,
  errors: [],
  onBlur: _ => _,
}

export default NumberField

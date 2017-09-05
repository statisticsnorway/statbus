import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const TextField = ({
  name, value, label: labelKey, title, placeholder,
  touched, required, errors, disabled,
  setFieldValue, onBlur, localize,
}) => {
  const hasErrors = touched && errors.length !== 0
  const label = localize(labelKey)
  const handleChange = (_, { value: nextValue }) => {
    setFieldValue(name, nextValue)
  }
  return (
    <div className="field">
      <Form.Input
        type="text"
        name={name}
        label={label}
        title={title || label}
        placeholder={localize(placeholder)}
        value={value !== null ? value : ''}
        onChange={handleChange}
        onBlur={onBlur}
        required={required}
        error={hasErrors}
        disabled={disabled}
      />
      {hasErrors &&
        <Message title={label} list={errors.map(localize)} error />}
    </div>
  )
}

TextField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: oneOfType([number, string]),
  required: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  disabled: bool,
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

TextField.defaultProps = {
  value: '',
  title: undefined,
  placeholder: undefined,
  required: false,
  errors: [],
  disabled: false,
  onBlur: _ => _,
}

export default TextField

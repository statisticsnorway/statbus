import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'

const NumberField = ({
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
  const handleChange = (_, { value: nextValue }) => {
    setFieldValue(name, hasValue(nextValue) ? nextValue : null)
  }
  const hasErrors = touched && hasValue(errorKeys)
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  return (
    <div className="field">
      <Form.Input
        type="number"
        name={name}
        label={label}
        title={title}
        placeholder={placeholder}
        value={value != null ? value : ''}
        onChange={handleChange}
        onBlur={onBlur}
        onKeyDown={onKeyDown}
        required={required}
        error={hasErrors}
        disabled={disabled}
        inline={inline}
        width={width}
      />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
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
  disabled: bool,
  inline: bool,
  width: oneOfType([string, number]),
  setFieldValue: func.isRequired,
  onBlur: func,
  onKeyDown: func,
  localize: func.isRequired,
}

NumberField.defaultProps = {
  value: '',
  title: undefined,
  placeholder: undefined,
  required: false,
  errors: [],
  disabled: false,
  inline: false,
  width: undefined,
  onBlur: _ => _,
  onKeyDown: undefined,
}

export default NumberField

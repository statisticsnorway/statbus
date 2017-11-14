import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string, oneOf } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const TextField = ({
  name,
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  required,
  errors: errorKeys,
  disabled,
  type,
  inline,
  width,
  setFieldValue,
  onBlur,
  onKeyDown,
  localize,
}) => {
  const handleChange = (_, { value: nextValue }) => {
    setFieldValue(name, nextValue)
  }
  const hasErrors = touched && errorKeys.length !== 0
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  return (
    <div className="field">
      <Form.Input
        type={type}
        name={name}
        label={label}
        title={title}
        placeholder={placeholder}
        value={value !== null ? value : ''}
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

TextField.propTypes = {
  name: string.isRequired,
  type: oneOf(['email', 'password', 'tel', 'text']),
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: oneOfType([number, string]),
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

TextField.defaultProps = {
  value: '',
  type: 'text',
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

export default TextField

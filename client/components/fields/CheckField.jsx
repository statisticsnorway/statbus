import React from 'react'
import { arrayOf, func, string, bool, number, oneOfType } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const CheckField = ({
  name,
  value,
  label: labelKey,
  title: titleKey,
  touched,
  errors: errorKeys,
  disabled,
  width,
  setFieldValue,
  onBlur,
  localize,
}) => {
  const handleChange = (_, { checked: nextValue }) => {
    setFieldValue(name, nextValue)
  }
  const hasErrors = touched && errorKeys.length !== 0
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  return (
    <div className="field">
      <label htmlFor={name}>&nbsp;</label>
      <Form.Checkbox
        id={name}
        label={label}
        title={title}
        checked={value}
        onChange={handleChange}
        onBlur={onBlur}
        error={hasErrors}
        disabled={disabled}
        width={width}
      />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

CheckField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  value: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  disabled: bool,
  width: oneOfType([number, string]),
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

CheckField.defaultProps = {
  value: false,
  title: undefined,
  errors: [],
  disabled: false,
  width: undefined,
  onBlur: _ => _,
}

export default CheckField

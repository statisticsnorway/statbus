import React from 'react'
import PropTypes from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const CheckField = ({
  name, value, label: labelKey, title: titleKey,
  touched, errors: errorKeys, disabled,
  setFieldValue, onBlur, localize,
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
      />
      {hasErrors &&
        <Message title={label} list={errorKeys.map(localize)} error />}
    </div>
  )
}

const { arrayOf, func, string, bool } = PropTypes
CheckField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  value: bool,
  touched: bool.isRequired,
  errors: arrayOf(string),
  disabled: bool,
  setFieldValue: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

CheckField.defaultProps = {
  value: false,
  title: undefined,
  errors: [],
  disabled: false,
  onBlur: _ => _,
}

export default CheckField

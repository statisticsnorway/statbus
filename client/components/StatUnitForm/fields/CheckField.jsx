import React from 'react'
import { arrayOf, func, string, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

const CheckField = ({
  name, value, label: labelKey, title,
  touched, errors,
  onChange, onBlur, localize,
}) => {
  const hasErrors = touched && errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <label htmlFor={name}>&nbsp;</label>
      <Form.Checkbox
        id={name}
        label={label}
        title={title || label}
        value={value}
        onChange={onChange}
        onBlur={onBlur}
        error={hasErrors}
      />
      {hasErrors &&
        <Message title={label} list={errors.map(localize)} error />}
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
  onChange: func.isRequired,
  onBlur: func,
  localize: func.isRequired,
}

CheckField.defaultProps = {
  value: false,
  title: undefined,
  errors: [],
  onBlur: _ => _,
}

export default CheckField

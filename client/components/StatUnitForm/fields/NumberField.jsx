import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message } from 'semantic-ui-react'

import Form from 'components/Form'

const NumberField = ({
  name, value, required, labelKey, localize, errors, onChange,
}) => {
  const handleChange = (_, { value: val }) => { onChange({ name, value: val }) }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <Form.Text
        name={name}
        value={value !== null ? value : 0}
        onChange={handleChange}
        required={required}
        error={hasErrors}
        label={label}
      />
      <Form.Error at={name} />
      {hasErrors && <Message error title={label} list={errors.map(localize)} />}
    </div>
  )
}

NumberField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: oneOfType([number, string]),
  required: bool,
  labelKey: string.isRequired,
  onChange: func.isRequired,
  errors: arrayOf(string),
}

NumberField.defaultProps = {
  value: 0,
  required: false,
  errors: [],
}

export default NumberField

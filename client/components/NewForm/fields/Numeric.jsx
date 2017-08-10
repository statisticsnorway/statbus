import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message } from 'semantic-ui-react'

import Form from 'components/SchemaForm'

const Numeric = ({
  name, value, required, labelKey, localize, errors, onChange,
}) => {
  const handleChange = (val) => {
    onChange({ name, value: val === undefined || val === '' || val === null ? null : val })
  }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <Form.Text
        name={name}
        value={value}
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

Numeric.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: oneOfType([string, number]),
  required: bool,
  labelKey: string.isRequired,
  onChange: func.isRequired,
  errors: arrayOf(string),
}

Numeric.defaultProps = {
  value: '',
  required: false,
  errors: [],
}

export default Numeric

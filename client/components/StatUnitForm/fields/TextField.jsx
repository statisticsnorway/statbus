import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message } from 'semantic-ui-react'

import Form from 'components/Form'

const TextField = ({
  name, value, required, labelKey, localize, errors, onChange,
}) => {
  const handleChange = (_, { value: val }) => { onChange({ name, value: val }) }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <Form.Text
        name={name}
        value={value !== null ? value : ''}
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

TextField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: oneOfType([number, string]),
  labelKey: string.isRequired,
  onChange: func.isRequired,
  required: bool,
  errors: arrayOf(string),
}

TextField.defaultProps = {
  value: '',
  required: false,
  errors: [],
}

export default TextField

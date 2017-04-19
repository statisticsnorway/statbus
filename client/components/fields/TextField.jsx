import React from 'react'
import { Form } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TextField = ({ name, value, required, labelKey, localize, errors, onChange }) => (
  <div className="field">
    <Form.Input
      name={name}
      value={value !== null ? value : ''}
      onChange={onChange}
      label={localize(labelKey)}
      required={required}
      error={errors.length !== 0}
    />
  </div>
)

const { arrayOf, bool, func, number, oneOfType, string } = React.PropTypes

TextField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: oneOfType([number, string]),
  required: bool,
  labelKey: string.isRequired,
  onChange: func.isRequired,
  errors: arrayOf(string).isRequired,
}

TextField.defaultProps = {
  value: '',
  required: false,
}

export default wrapper(TextField)

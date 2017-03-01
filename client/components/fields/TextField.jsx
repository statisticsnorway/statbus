import React from 'react'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TextField = ({ name, value, required, labelKey, localize, errors, onChange }) => (
  <div>
    <Form.Input
      name={name}
      value={value || ''}
      onChange={onChange}
      label={localize(labelKey)}
      required={required}
      error={errors.length !== 0}
    />
    {errors.map(er => <Message key={`${name}_${er}`} content={er} error />)}
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

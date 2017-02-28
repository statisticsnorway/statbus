import React from 'react'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TextField = ({ name, value, labelKey, localize, errors, onChange }) => (
  <div>
    <Form.Input
      name={name}
      value={value}
      onChange={onChange}
      label={localize(labelKey)}
      error={errors.length !== 0}
    />
    {errors.map(er => <Message key={`${name}_${er}`} content={er} error />)}
  </div>
)

const { arrayOf, func, number, oneOfType, string } = React.PropTypes

TextField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: oneOfType([number, string]).isRequired,
  labelKey: string.isRequired,
  onChange: func.isRequired,
  errors: arrayOf(string).isRequired,
}

export default wrapper(TextField)

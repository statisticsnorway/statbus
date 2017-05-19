import React from 'react'
import { Message } from 'semantic-ui-react'

import Form from 'components/Form'

const CheckField = ({
  name, value, labelKey, localize, onChange, errors,
}) => {
  const handleChange = (_, { checked }) => { onChange({ name, value: checked }) }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field">
      <label htmlFor={name}>&nbsp;</label>
      <Form.Checkbox
        id={name}
        name={name}
        checked={value}
        onChange={handleChange}
        error={hasErrors}
        label={label}
      />
      <Form.Error at={name} />
      {hasErrors && <Message error title={label} list={errors.map(localize)} />}
    </div>
  )
}

const { arrayOf, func, string, bool } = React.PropTypes

CheckField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: bool,
  onChange: func.isRequired,
  labelKey: string.isRequired,
  errors: arrayOf(string),
}

CheckField.defaultProps = {
  value: false,
  errors: [],
}

export default CheckField

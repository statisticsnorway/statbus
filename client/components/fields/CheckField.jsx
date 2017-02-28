import React from 'react'
import { Checkbox } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const CheckField = ({ name, value, labelKey, localize, onChange }) => (
  <Checkbox
    name={name}
    checked={value}
    onChange={onChange}
    label={localize(labelKey)}
  />
)

const { func, string, bool } = React.PropTypes

CheckField.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  value: bool.isRequired,
  onChange: func.isRequired,
  labelKey: string.isRequired,
}

export default wrapper(CheckField)

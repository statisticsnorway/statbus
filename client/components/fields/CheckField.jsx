import React from 'react'
import { Checkbox } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const CheckField = ({ name, value, labelKey, localize, onChange }) => (
  <div className="field">
    <label>&nbsp;</label>
    <Checkbox
      name={name}
      checked={value}
      onChange={(e, obj) => onChange(e, { name: obj.name, value: obj.checked })}
      label={localize(labelKey)}
    />
  </div>
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

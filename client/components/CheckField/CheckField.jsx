import React from 'react'
import { Checkbox } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'

const CheckField = ({ item, localize }) => (
  <Checkbox
    defaultChecked={item.value}
    name={item.name}
    label={localize(item.localizeKey)}
  />
)

const { func, shape, string, bool } = React.PropTypes

CheckField.propTypes = {
  localize: func,
  item: shape({
    name: string,
    value: bool,
  }),
}

export default wrapper(CheckField)

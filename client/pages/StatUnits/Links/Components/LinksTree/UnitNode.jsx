import React from 'react'
import { func, string, number } from 'prop-types'
import R from 'ramda'
import { Icon } from 'semantic-ui-react'
import shouldUpdate from 'recompose/shouldUpdate'

import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const UnitNode = ({ localize, code, name, type }) => (
  <span>
    <Icon name={statUnitIcons(type)} title={localize(statUnitTypes.get(type))} />
    {code && <strong>{code}:</strong>} {name}
  </span>
)

UnitNode.propTypes = {
  localize: func.isRequired,
  code: string,
  name: string.isRequired,
  type: number.isRequired,
}

UnitNode.defaultProps = {
  code: '',
}

export default shouldUpdate((props, nextProps) => !R.equals(props, nextProps))(UnitNode)

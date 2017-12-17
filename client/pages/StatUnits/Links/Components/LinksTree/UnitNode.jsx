import React from 'react'
import { func, string, number } from 'prop-types'
import { equals } from 'ramda'
import { Icon } from 'semantic-ui-react'
import shouldUpdate from 'recompose/shouldUpdate'

import { statUnitTypes, statUnitIcons } from 'helpers/enums'

const UnitNode = ({ localize, code, name, type }) => (
  <span>
    <Icon name={statUnitIcons.get(type)} title={localize(statUnitTypes.get(type))} />
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

export default shouldUpdate((props, nextProps) => !equals(props, nextProps))(UnitNode)

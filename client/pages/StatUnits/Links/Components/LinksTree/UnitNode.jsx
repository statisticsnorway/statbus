import React from 'react'
import { func, string, number } from 'prop-types'
import { equals } from 'ramda'
import { Icon, Popup } from 'semantic-ui-react'
import shouldUpdate from 'recompose/shouldUpdate'

import { statUnitTypes, statUnitIcons } from 'helpers/enums'
import { getNewName } from 'helpers/locale'

const UnitNode = (props) => {
  const { localize, code, type } = props
  return (
    <Popup
      trigger={
        <span>
          <Icon name={statUnitIcons.get(type)} title={localize(statUnitTypes.get(type))} />
          {code && <strong>{code}:</strong>} {getNewName(props, false)}
        </span>
      }
      content={localize(statUnitTypes.get(type))}
      position="right center"
    />
  )
}

UnitNode.propTypes = {
  localize: func.isRequired,
  code: string,
  type: number.isRequired,
}

UnitNode.defaultProps = {
  code: '',
}

export default shouldUpdate((props, nextProps) => !equals(props, nextProps))(UnitNode)

import React from 'react'
import { Button, Item, Icon } from 'semantic-ui-react'
import { Link } from 'react-router'

import { dataAccessAttribute as checkDAA, systemFunction as checkSF } from 'helpers/checkPermissions'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const ListItem = ({ localize, statUnit, restore }) => {
  const handleClick = () => {
    const msg = `${localize('UndeleteMessage')}. ${localize('AreYouSure')}`
    if (confirm(msg)) {
      restore(statUnit.type, statUnit.regId)
    }
  }
  const address = statUnit.address
    ? Object.values(statUnit.address).join(' ')
    : ''
  return (
    <Item>
      <Icon
        name={statUnitIcons(statUnit.type)}
        size="large"
        title={statUnitTypes.get(statUnit.type).value}
      />
      <Item.Content>
        <Item.Header
          content={checkSF('StatUnitEdit')
            ? <Link to={`/statunits/view/${statUnit.type}/${statUnit.regId}`}>{statUnit.name}</Link>
            : <span>{statUnit.name}</span>}
        />
        <Item.Meta
          content={<span>{localize(statUnitTypes.get(statUnit.unitType))}</span>}
        />
        <Item.Description>
          <p>{localize('RegId')}: {statUnit.regId}</p>
          {checkDAA('Address') && <p>{localize('Address')}: {address}</p>}
        </Item.Description>
      </Item.Content>
      <Item.Content>
        <Button
          onClick={handleClick}
          content={localize('Restore')}
          floated="right"
          icon="undo"
          color="green"
          size="tiny"
        />
      </Item.Content>
    </Item>
  )
}

const { number, string, func, shape } = React.PropTypes

ListItem.propTypes = {
  localize: func.isRequired,
  restore: func.isRequired,
  statUnit: shape({
    regId: number.isRequired,
    type: number.isRequired,
    name: string.isRequired,
  }).isRequired,
}

export default ListItem

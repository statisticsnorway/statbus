import React from 'react'
import { Link } from 'react-router'
import { Button, Item, List } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const ListItem = ({ deleteStatUnit, ...statUnit, localize }) => {
  const handleDelete = () => {
    if (confirm(`'${localize('DeleteStatUnitMessage')}' '${statUnit.name}'. '${localize('AreYouSure')}'?`)) {
      deleteStatUnit(statUnit.id)
    }
  }
  const address = statUnit.address
    ? Object.values(statUnit.address).join(' ')
    : ''
  const title = statUnitTypes.get(statUnit.type).value
  return (
    <Item>
      <List.Icon
        name={statUnitIcons(statUnit.type)}
        size="large"
        verticalAlign="middle"
        title={title}
      />
      <Item.Content>
        <Item.Header
          content={sF('StatUnitEdit')
            ? <Link to={`/statunits/view/${statUnit.regId}`}>{statUnit.name}</Link>
            : <span>{statUnit.name}</span>}
        />
        <Item.Meta>
          <span>{localize(statUnitTypes.get(statUnit.unitType))}</span>
        </Item.Meta>
        <Item.Description>
          <p>{localize('Address')}: {address}</p>
          <p>{localize('RegId')}: {statUnit.regId}</p>
        </Item.Description>
        <Item.Extra>
          {sF('StatUnitDelete') && <Button onClick={handleDelete} floated='right' negative>{localize('DeleteButton')}</Button>}
          {sF('StatUnitEdit') && <Link to={`/statunits/edit/${statUnit.regId}`} floated='right'>edit</Link>}
        </Item.Extra>
      </Item.Content>
    </Item>
  )
}

ListItem.propTypes = { localize: React.PropTypes.string.isRequired }

export default wrapper(ListItem)

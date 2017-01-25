import React from 'react'
import { Link } from 'react-router'
import { Button, Item, List } from 'semantic-ui-react'

import { dataAccessAttribute as checkDAA, systemFunction as checkSF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const ListItem = ({ deleteStatUnit, ...statUnit, localize }) => {
  const handleDelete = () => {
    const msg = `${localize('DeleteStatUnitMessage')} '${statUnit.name}'. ${localize('AreYouSure')}?`
    if (confirm(msg)) {
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
          content={checkSF('StatUnitEdit')
            ? <Link to={`/statunits/view/${statUnit.type}/${statUnit.regId}`}>{statUnit.name}</Link>
            : <span>{statUnit.name}</span>}
        />
        <Item.Meta>
          <span>{localize(statUnitTypes.get(statUnit.unitType))}</span>
        </Item.Meta>
        <Item.Description>
          <p>{localize('RegId')}: {statUnit.regId}</p>
          {checkDAA('Address') && <p>{localize('Address')}: {address}</p>}
        </Item.Description>
        <Item.Extra>
          {checkSF('StatUnitDelete')
            && <Button onClick={handleDelete} floated="right" icon="remove" negative />}
          {checkSF('StatUnitEdit')
            && <Button
              as={Link}
              to={`/statunits/edit/${statUnit.type}/${statUnit.regId}`}
              icon="edit"
              primary
            />}
        </Item.Extra>
      </Item.Content>
    </Item>
  )
}

ListItem.propTypes = { localize: React.PropTypes.string.isRequired }

export default wrapper(ListItem)

import React from 'react'
import { Link } from 'react-router'
import { Button, Item, Icon } from 'semantic-ui-react'

import { dataAccessAttribute as checkDAA, systemFunction as checkSF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const ListItem = ({ deleteStatUnit, ...statUnit, localize }) => {
  const handleDelete = () => {
    const msg = `${localize('DeleteStatUnitMessage')} '${statUnit.name}'. ${localize('AreYouSure')}?`
    if (confirm(msg)) {
      deleteStatUnit(statUnit.type, statUnit.regId)
    }
  }
  const address = statUnit.address
    ? Object.values(statUnit.address).join(' ')
    : ''
  const title = statUnitTypes.get(statUnit.type).value
  return (
    <Item>
      <Icon name={statUnitIcons(statUnit.type)} size="large" title={title} />
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

ListItem.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(ListItem)

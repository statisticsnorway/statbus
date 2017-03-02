import React from 'react'
import { Button, Item, Icon } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

const ListItem = ({ localize, statUnit, restore }) => {
  const handleClick = () => {
    const msg = `${localize('UndeleteMessage')}. ${localize('AreYouSure')}`
    if (confirm(msg)) {
      restore(statUnit.type, statUnit.regId)
    }
  }

  return (
    <Item>
      <Icon
        name={statUnitIcons(statUnit.type)}
        size="large"
        verticalAlign="middle"
        title={statUnitTypes.get(statUnit.type).value}
      />
      <Item.Content>
        <Item.Header content={statUnit.name} />
        <Item.Description content={statUnit.type} />
        <Item.Extra>
          <Button onClick={handleClick} icon="undo" color="orange" size="tiny">
            {localize('Restore')}
          </Button>
        </Item.Extra>
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

export default wrapper(ListItem)

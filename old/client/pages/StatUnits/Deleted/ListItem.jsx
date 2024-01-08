import React from 'react'
import { number, string, func, shape } from 'prop-types'
import { Button, Item, Icon, Popup } from 'semantic-ui-react'
import { Link } from 'react-router'

import { canRead, checkSystemFunction as checkSF } from '/helpers/config'
import { statUnitTypes, statUnitIcons } from '/helpers/enums'
import { getNewName } from '/helpers/locale'

const ListItem = ({ localize, statUnit, restore }) => {
  const address = statUnit.address ? getNewName(statUnit.address) : ''
  const title = statUnitTypes.get(statUnit.type)
  return (
    <Item>
      <Icon name={statUnitIcons.get(statUnit.type)} size="large" title={localize(title)} />
      <Item.Content>
        <Item.Header
          content={
            checkSF('StatUnitView') ? (
              <Link to={`/statunits/view/${statUnit.type}/${statUnit.regId}`}>{statUnit.name}</Link>
            ) : (
              <span>{statUnit.name}</span>
            )
          }
        />
        <Item.Meta content={<span>{localize(title)}</span>} />
        <Item.Description>
          <p>
            {localize('StatId')}: {statUnit.statId}
          </p>
          {canRead('Address') && (
            <p>
              {localize('Address')}: {address}
            </p>
          )}
        </Item.Description>
      </Item.Content>
      <Item.Content>
        <Popup
          content={localize('YouDontHaveEnoughtRightsRegionOrActivity')}
          disabled={!statUnit.readonly}
          trigger={
            <Button
              onClick={() => restore(statUnit)}
              floated="right"
              icon="undo"
              color="green"
              size="tiny"
              disabled={statUnit.readonly}
            />
          }
        />
      </Item.Content>
    </Item>
  )
}

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

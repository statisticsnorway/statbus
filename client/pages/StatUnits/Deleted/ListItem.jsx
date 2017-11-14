import React from 'react'
import { number, string, func, shape } from 'prop-types'
import { Button, Item, Icon } from 'semantic-ui-react'
import { Link } from 'react-router'

import {
  checkDataAccessAttribute as checkDAA,
  checkSystemFunction as checkSF,
} from 'helpers/config'
import { statUnitTypes, statUnitIcons } from 'helpers/enums'

const ListItem = ({ localize, statUnit, restore }) => {
  const address = statUnit.address ? Object.values(statUnit.address).join(' ') : ''
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
            {localize('RegId')}: {statUnit.regId}
          </p>
          {checkDAA('Address') && (
            <p>
              {localize('Address')}: {address}
            </p>
          )}
        </Item.Description>
      </Item.Content>
      <Item.Content>
        <Button
          onClick={() => restore(statUnit)}
          floated="right"
          icon="undo"
          color="green"
          size="tiny"
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

import React from 'react'
import { number, string, func, shape } from 'prop-types'
import { Link } from 'react-router'
import { Button, Item, Icon } from 'semantic-ui-react'

import {
  checkDataAccessAttribute as checkDAA,
  checkSystemFunction as checkSF,
} from 'helpers/config'
import { statUnitTypes, statUnitIcons } from 'helpers/enums'

const ListItem = ({ deleteStatUnit, statUnit, localize }) => {
  const address = statUnit.address
    ? `${statUnit.address.addressPart1 || ''} ${statUnit.address.addressPart2 || ''} ${statUnit
      .address.addressPart3 || ''}`
    : ''
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
        <Item.Extra>
          {checkSF('StatUnitDelete') && (
            <Button
              onClick={() => deleteStatUnit(statUnit)}
              floated="right"
              icon="trash"
              negative
            />
          )}
          {checkSF('StatUnitEdit') && (
            <Button
              as={Link}
              to={`/statunits/edit/${statUnit.type}/${statUnit.regId}`}
              icon="edit"
              primary
            />
          )}
        </Item.Extra>
      </Item.Content>
    </Item>
  )
}

ListItem.propTypes = {
  statUnit: shape({
    regId: number.isRequired,
    type: number.isRequired,
    name: string.isRequired,
  }).isRequired,
  deleteStatUnit: func.isRequired,
  localize: func.isRequired,
}

export default ListItem

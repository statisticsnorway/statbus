import React from 'react'
import { number, string, func, shape } from 'prop-types'
import { Link } from 'react-router'
import { Button, Item, Icon } from 'semantic-ui-react'

import { canRead, checkSystemFunction as checkSF } from 'helpers/config'
import { statUnitTypes, statUnitIcons } from 'helpers/enums'

const ListItem = ({ statUnit, localize, lookups }) => {
  const title = statUnitTypes.get(statUnit.type)
  const legalForm = lookups[5].find(x => x.id === statUnit.legalFormId)
  return (
    <Item>
      <Icon name={statUnitIcons.get(statUnit.type)} size="large" title={localize(title)} />
      <Item.Content>
        <Item.Header
          content={
            checkSF('StatUnitView') ? (
              <Link to={`/statunits/view/${statUnit.type}/${statUnit.regId}`}>
                {statUnit.statId}
              </Link>
            ) : (
              <span>{statUnit.statId}</span>
            )
          }
        />
        <Item.Description>
          <p>
            {localize('Name')}: {statUnit.name}
          </p>
          {canRead('Address') && (
            <p>
              {localize('Region')}: {statUnit.address.regionFullPath}
            </p>
          )}
          {canRead('Address') && (
            <p>
              {localize('AddressPart1')}: {statUnit.address.addressPart1}
            </p>
          )}
          {canRead('Address') && (
            <p>
              {localize('AddressPart2')}: {statUnit.address.addressPart2}
            </p>
          )}
          {canRead('Address') && (
            <p>
              {localize('AddressPart3')}: {statUnit.address.addressPart3}
            </p>
          )}
          {canRead('LegalFormId', statUnit.type) && (
            <p>
              {localize('LegalForm')}: {legalForm && `${legalForm.code} ${legalForm.name}`}
            </p>
          )}
          {canRead('Persons', statUnit.type) && (
            <p>
              {localize('ContactPerson')}: {statUnit.persons.contactPerson}
            </p>
          )}
          {canRead('Activities', statUnit.type) && (
            <p>
              {localize('Activity')}: {statUnit.activities.name}
            </p>
          )}
          {canRead('TaxRegId', statUnit.type) && (
            <p>
              {localize('TaxRegId')}: {statUnit.taxRegId}
            </p>
          )}
        </Item.Description>
        <Item.Extra>
          {/* checkSF('StatUnitDelete') && (
            <Button
              onClick={() => deleteStatUnit(statUnit)}
              floated="right"
              icon="trash"
              negative
            />
          ) */}
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
  lookups: shape({}).isRequired,
}

export default ListItem

import React from 'react'
import { number, string, func, shape } from 'prop-types'
import { Link } from 'react-router'
import { Button, Item, Icon, List } from 'semantic-ui-react'

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
          <List size="tiny">
            <List.Item>
              <List.Content>
                <List.Header as="p">{localize('Name')}</List.Header>
                <List.Description>{statUnit.name}</List.Description>
              </List.Content>
            </List.Item>
            {canRead('Address') && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('Region')}</List.Header>
                  <List.Description>{statUnit.address.regionFullPath}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('Address') && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('AddressPart1')}</List.Header>
                  <List.Description>{statUnit.address.addressPart1}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('Address') && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('AddressPart2')}</List.Header>
                  <List.Description>{statUnit.address.addressPart2}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('Address') && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('AddressPart3')}</List.Header>
                  <List.Description>{statUnit.address.addressPart3}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('LegalFormId', statUnit.type) && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('LegalForm')}</List.Header>
                  <List.Description>
                    {legalForm && `${legalForm.code} ${legalForm.name}`}
                  </List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('Persons', statUnit.type) && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('ContactPerson')}</List.Header>
                  <List.Description>{statUnit.persons.contactPerson}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('Activities', statUnit.type) && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('ContactPerson')}</List.Header>
                  <List.Description>{statUnit.activities.name}</List.Description>
                </List.Content>
              </List.Item>
            )}
            {canRead('TaxRegId', statUnit.type) && (
              <List.Item>
                <List.Content>
                  <List.Header as="p">{localize('TaxRegId')}</List.Header>
                  <List.Description>{statUnit.taxRegId}</List.Description>
                </List.Content>
              </List.Item>
            )}
            <List.Item>
              <List.Content floated="right">
                {checkSF('StatUnitEdit') && (
                  <Button
                    as={Link}
                    to={`/statunits/edit/${statUnit.type}/${statUnit.regId}`}
                    icon="edit"
                    floated="right"
                    primary
                  />
                )}
              </List.Content>
            </List.Item>
          </List>
        </Item.Description>
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

import React from 'react'
import { number, string, func, shape, bool } from 'prop-types'
import { Link } from 'react-router'
import { Button, Table } from 'semantic-ui-react'

import { canRead, checkSystemFunction as checkSF } from 'helpers/config'
import { statUnitTypes } from 'helpers/enums'
import { getNewName } from 'helpers/locale'
import styles from './styles.pcss'

const ListItem = ({ statUnit, deleteStatUnit, localize, lookups, showLegalFormColumn }) => {
  const title = statUnitTypes.get(statUnit.type)
  const legalForm = lookups[5].find(x => x.id === statUnit.legalFormId)
  return (
    <Table.Body className={styles['table-body']}>
      <Table.Row>
        <Table.Cell>
          {checkSF('StatUnitView') ? (
            <Link to={`/statunits/view/${statUnit.type}/${statUnit.regId}`}>
              {`${statUnit.statId} - ${localize(title)}`}
            </Link>
          ) : (
            <span>{`${statUnit.statId} - ${localize(title)}`}</span>
          )}
        </Table.Cell>
        <Table.Cell>{statUnit.name}</Table.Cell>
        <Table.Cell>{canRead('Address') && statUnit.address.regionFullPath}</Table.Cell>
        <Table.Cell>{canRead('Address') && statUnit.address.addressPart1}</Table.Cell>
        <Table.Cell>{canRead('Address') && statUnit.address.addressPart2}</Table.Cell>
        <Table.Cell>{canRead('Address') && statUnit.address.addressPart3}</Table.Cell>
        {showLegalFormColumn && (
          <Table.Cell>
            {canRead('LegalFormId', statUnit.type) &&
              (legalForm && `${legalForm.code} ${getNewName(legalForm)}`)}
          </Table.Cell>
        )}
        <Table.Cell>
          {canRead('Persons', statUnit.type) && statUnit.persons.contactPerson}
        </Table.Cell>
        <Table.Cell>{canRead('Activities', statUnit.type) && statUnit.activities.name}</Table.Cell>
        <Table.Cell>{canRead('TaxRegId', statUnit.type) && statUnit.taxRegId}</Table.Cell>
        <Table.Cell singleLine>
          <div>
            {checkSF('StatUnitEdit') && (
              <Button
                as={Link}
                to={`/statunits/edit/${statUnit.type}/${statUnit.regId}`}
                icon="edit"
                primary
              />
            )}
            {checkSF('StatUnitDelete') && (
              <Button onClick={() => deleteStatUnit(statUnit)} icon="trash" negative />
            )}
          </div>
        </Table.Cell>
      </Table.Row>
    </Table.Body>
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
  showLegalFormColumn: bool.isRequired,
}

export default ListItem

import React from 'react'
import { number, string, func, shape, bool } from 'prop-types'
import { Table } from 'semantic-ui-react'

import { canRead, checkSystemFunction as checkSF } from '/client/helpers/config'
import { statUnitTypes } from '/client/helpers/enums'
import { getNewName } from '/client/helpers/locale'
import styles from './styles.scss'

const ListItem = ({ statUnit, deleteStatUnit, localize, lookups, showLegalFormColumn }) => {
  const title = statUnitTypes.get(statUnit.type)

  const viewStatUnit = () => {
    window.location.href = `/statunits/view/${statUnit.type}/${statUnit.regId}`
  }

  return (
    <Table.Body className={styles['table-body']}>
      <Table.Row style={{ cursor: 'pointer' }} onClick={viewStatUnit}>
        <Table.Cell>
          {checkSF('StatUnitView') ? (
            `${statUnit.statId} - ${localize(title)}`
          ) : (
            <span>{`${statUnit.statId} - ${localize(title)}`}</span>
          )}
        </Table.Cell>
        <Table.Cell>{statUnit.name}</Table.Cell>
        <Table.Cell>
          {canRead('Activities', statUnit.type) && getNewName(statUnit.activities)}
        </Table.Cell>
        <Table.Cell />
        <Table.Cell />
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

import React from 'react'
import { number, string, func, shape, bool } from 'prop-types'
import { Table } from 'semantic-ui-react'

import { canRead, checkSystemFunction as checkSF } from '/helpers/config'
import { statUnitTypes } from '/helpers/enums'
import { getNewName } from '/helpers/locale'
import styles from './styles.scss'

const ListItem = ({ statUnit, localize }) => {
  const title = statUnitTypes.get(statUnit.type)

  const viewStatUnit = () => {
    window.location.href = `/statunits/view/${statUnit.type}/${statUnit.regId}`
  }

  return (
    <Table.Body className={styles['table-body']}>
      <Table.Row style={{ cursor: 'pointer' }} onClick={viewStatUnit}>
        <Table.Cell style={{ verticalAlign: 'middle' }}>
          <img
            style={{ width: '25px', marginBottom: '-7px', marginRight: '7px' }}
            src={`icons/${statUnitTypes.get(statUnit.type)}.png`}
            title={localize(title)}
            alt={statUnitTypes.get(statUnit.type)}
          />
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
  localize: func.isRequired,
  lookups: shape({}).isRequired,
  showLegalFormColumn: bool.isRequired,
}

export default ListItem

import React from 'react'
import { Table } from 'semantic-ui-react'

import LinksGridRow from './LinksGridRow'

const { func, arrayOf, shape, string, object } = React.PropTypes

class LinksGrid extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    deleteLink: func.isRequired,
    data: arrayOf(shape({
      source1: object.isRequired,
      source2: object.isRequired,
      comment: string.isRequired,
    })).isRequired,
  }

  render() {
    const { data, localize, deleteLink } = this.props
    return (
      <Table selectable celled compact size="small">
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell width={1}>{localize('RowIndex')}</Table.HeaderCell>
            <Table.HeaderCell width={3}>{localize('StatUnit')} 1</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('UnitType')}</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('StatId')}</Table.HeaderCell>
            <Table.HeaderCell width={3}>{localize('StatUnit')} 2</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('UnitType')}</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('StatId')}</Table.HeaderCell>
            <Table.HeaderCell width={1}>&nbsp;</Table.HeaderCell>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {data.map((v, ix) => (
            <LinksGridRow
              key={`Row_${v.source1.id}_${v.source1.type}_${v.source2.id}_${v.source2.type}`}
              index={ix + 1}
              data={v}
              localize={localize}
              deleteLink={deleteLink}
            />
          ))}
          {data.length === 0 &&
            <Table.Row>
              <Table.Cell colSpan={8} textAlign="center">{localize('TableNoRecords')}</Table.Cell>
            </Table.Row>
          }
        </Table.Body>
      </Table>
    )
  }
}

export default LinksGrid

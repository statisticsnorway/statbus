import React from 'react'
import { func, arrayOf, shape, object, bool } from 'prop-types'
import { Table } from 'semantic-ui-react'
import { equals } from 'ramda'

import LinksGridRow from './LinksGridRow'

class LinksGrid extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    deleteLink: func,
    data: arrayOf(shape({
      source1: object.isRequired,
      source2: object.isRequired,
    })).isRequired,
    readOnly: bool,
  }

  static defaultProps = {
    readOnly: false,
    deleteLink: v => v,
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !equals(this.props, nextProps) || !equals(this.state, nextState)
  }

  render() {
    const { data, localize, deleteLink, readOnly } = this.props
    return (
      <Table selectable celled compact size="small">
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell width={1}>{localize('RowIndex')}</Table.HeaderCell>
            <Table.HeaderCell width={3 + readOnly}>{localize('StatUnit')} 1</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('UnitType')}</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('StatId')}</Table.HeaderCell>
            <Table.HeaderCell width={3}>{localize('StatUnit')} 2</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('UnitType')}</Table.HeaderCell>
            <Table.HeaderCell width={2}>{localize('StatId')}</Table.HeaderCell>
            {!readOnly && <Table.HeaderCell width={1}>&nbsp;</Table.HeaderCell>}
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
              readOnly={readOnly}
            />
          ))}
          {data.length === 0 && (
            <Table.Row>
              <Table.Cell colSpan={7 + readOnly} textAlign="center">
                {localize('TableNoRecords')}
              </Table.Cell>
            </Table.Row>
          )}
        </Table.Body>
      </Table>
    )
  }
}

export default LinksGrid

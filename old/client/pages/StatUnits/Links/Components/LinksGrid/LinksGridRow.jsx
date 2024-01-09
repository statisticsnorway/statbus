import React from 'react'
import { func, shape, string, number, bool } from 'prop-types'
import { Table, Icon, Popup } from 'semantic-ui-react'

import { checkSystemFunction as sF } from '/helpers/config'
import { statUnitTypes } from '/helpers/enums'

const shapeOfSource = shape({
  code: string,
  name: string,
  type: number,
})

class LinksGridRow extends React.Component {
  static propTypes = {
    index: number.isRequired,
    localize: func.isRequired,
    deleteLink: func.isRequired,
    data: shape({
      source1: shapeOfSource.isRequired,
      source2: shapeOfSource.isRequired,
    }).isRequired,
    readOnly: bool.isRequired,
  }

  onDeleteClick = () => {
    const { data, deleteLink } = this.props
    deleteLink(data)
  }
  render() {
    const {
      index,
      data: { source1, source2 },
      localize,
      readOnly,
    } = this.props
    return (
      <Table.Row>
        <Table.Cell>{index}</Table.Cell>
        <Table.Cell>{source1.name}</Table.Cell>
        <Table.Cell>{localize(statUnitTypes.get(source1.type))}</Table.Cell>
        <Table.Cell>{source1.code}</Table.Cell>
        <Table.Cell> {source2.name}</Table.Cell>
        <Table.Cell>{localize(statUnitTypes.get(source2.type))}</Table.Cell>
        <Table.Cell>{source2.code}</Table.Cell>
        {!readOnly && (
          <Table.Cell textAlign="center">
            {sF('LinksDelete') && (
              <div>
                <Popup
                  trigger={<Icon name="trash" color="red" onClick={this.onDeleteClick} />}
                  content={localize('ButtonDelete')}
                  size="mini"
                />
              </div>
            )}
          </Table.Cell>
        )}
      </Table.Row>
    )
  }
}

export default LinksGridRow

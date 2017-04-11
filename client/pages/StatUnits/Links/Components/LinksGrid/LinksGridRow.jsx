import React from 'react'
import { Table, Icon, Confirm, Popup } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'

const { func, shape, string, number } = React.PropTypes

const shapeOfSource = shape({
  code: string.isRequired,
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
  }

  state = {
    confirm: false,
  }

  onDeleteClick = () => {
    this.setState({ confirm: true })
  }

  handleCancel = () => {
    this.setState({ confirm: false })
  }

  handleConfirm = () => {
    const { data, deleteLink } = this.props
    this.setState({ confirm: false })
    deleteLink(data)
  }

  render() {
    const { index, data: { source1, source2 }, localize } = this.props
    const { confirm } = this.state
    return (
      <Table.Row>
        <Table.Cell>{index}</Table.Cell>
        <Table.Cell>{source1.name}</Table.Cell>
        <Table.Cell>{localize(statUnitTypes.get(source1.type))}</Table.Cell>
        <Table.Cell>{source1.code}</Table.Cell>
        <Table.Cell>{source2.name}</Table.Cell>
        <Table.Cell>{localize(statUnitTypes.get(source2.type))}</Table.Cell>
        <Table.Cell>{source2.code}</Table.Cell>
        <Table.Cell textAlign="center">
          <Popup
            trigger={<Icon name="trash" color="red" onClick={this.onDeleteClick} />}
            content={localize('ButtonDelete')}
            size="mini"
          />
          <Confirm
            open={confirm}
            cancelButton={localize('No')}
            confirmButton={localize('Yes')}
            header={localize('DialogTitleDelete')}
            content={localize('DialogBodyDelete')}
            onCancel={this.handleCancel}
            onConfirm={this.handleConfirm}
          />
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default LinksGridRow

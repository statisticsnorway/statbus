import React from 'react'
import { Button, Table, Confirm } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const { func, shape, number, string, bool } = React.PropTypes

class RegionsListItem extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    data: shape({
      id: number.isRequired,
      name: string.isRequired,
    }).isRequired,
    onDelete: func.isRequired,
    onEdit: func.isRequired,
    readonly: bool.isRequired,
  }
  state = {
    confirmShow: false,
  }
  handleEdit = () => {
    const { onEdit, data } = this.props
    onEdit(data.id)
  }
  showConfirm = () => {
    this.setState({ confirmShow: true })
  }
  handleCancel = () => {
    this.setState({ confirmShow: false })
  }
  handleConfirm = () => {
    this.props.onDelete(this.props.data.id)
  }
  render() {
    const { data, localize, readonly } = this.props
    const { confirmShow } = this.state
    return (
      <Table.Row>
        <Table.Cell width={14}>
          {data.name}
        </Table.Cell>
        <Table.Cell width={2} textAlign="right">
          <Button.Group>
            <Button icon="edit" color="blue" onClick={this.handleEdit} disabled={readonly} />
            <Button icon="trash" color="red" onClick={this.showConfirm} disabled={readonly} />
            <Confirm
              open={confirmShow}
              onCancel={this.handleCancel}
              onConfirm={this.handleConfirm}
              content={`${localize('RegionDeleteMessage')} '${data.name}'?`}
              header={`${localize('AreYouSure')}?`}
            />
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default wrapper(RegionsListItem)

import React from 'react'
import { func, shape, number, string, bool } from 'prop-types'
import { Button, Table, Confirm } from 'semantic-ui-react'

import { checkSystemFunction as sF } from 'helpers/config'

class RegionsListItem extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    data: shape({
      id: number.isRequired,
      code: string.isRequired,
      name: string.isRequired,
      adminstrativeCenter: string,
      isDeleted: bool,
    }).isRequired,
    onToggleDelete: func.isRequired,
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
    this.props.onToggleDelete(this.props.data.id, !this.props.data.isDeleted)
    this.setState({ confirmShow: false })
  }
  render() {
    const { data, localize, readonly } = this.props
    const { confirmShow } = this.state
    return (
      <Table.Row>
        <Table.Cell>{data.code}</Table.Cell>
        <Table.Cell>{data.name}</Table.Cell>
        <Table.Cell>{data.adminstrativeCenter}</Table.Cell>
        <Table.Cell textAlign="right">
          <Button.Group size="mini">
            {sF('RegionsEdit') && (
              <Button
                icon="edit"
                color="blue"
                onClick={this.handleEdit}
                disabled={readonly || data.isDeleted}
              />
            )}
            {sF('RegionsDelete') && (
              <Button
                icon={data.isDeleted ? 'undo' : 'trash'}
                color={data.isDeleted ? 'green' : 'red'}
                onClick={this.showConfirm}
                disabled={readonly}
              />
            )}
            <Confirm
              open={confirmShow}
              onCancel={this.handleCancel}
              onConfirm={this.handleConfirm}
              content={`${localize(data.isDeleted ? 'RegionUndeleteMessage' : 'RegionDeleteMessage')} '${data.name}' ?`}
              header={`${localize('AreYouSure')}?`}
            />
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default RegionsListItem

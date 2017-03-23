import React from 'react'
import { Button, Table, Confirm } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { systemFunction as sF } from 'helpers/checkPermissions'

const { func, shape, number, string, bool } = React.PropTypes

class RegionsListItem extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    data: shape({
      id: number.isRequired,
      isDeleted: bool.isRequired,
      name: string.isRequired,
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
        <Table.Cell width={14}>
          {data.name}
        </Table.Cell>
        <Table.Cell width={2} textAlign="right">
          <Button.Group size="mini">
            {sF('RegionsEdit') &&
              <Button icon="edit" color="blue" onClick={this.handleEdit} disabled={readonly} />
            }
            {sF('RegionsDelete') &&
              <Button
                icon={data.isDeleted ? 'recycle' : 'trash'}
                color={data.isDeleted ? 'orange' : 'red'}
                onClick={this.showConfirm}
                disabled={readonly}
              />
            }
            <Confirm
              open={confirmShow}
              onCancel={this.handleCancel}
              onConfirm={this.handleConfirm}
              content={`${localize(data.isDeleted ? 'RegionUndeleteMessage' : 'RegionDeleteMessage')} '${data.name}'?`}
              header={`${localize('AreYouSure')}?`}
            />
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default wrapper(RegionsListItem)

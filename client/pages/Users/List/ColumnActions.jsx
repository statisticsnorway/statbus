import React from 'react'
import { Button, Confirm } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'


const { func, shape } = React.PropTypes
class ColumnActions extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    setUserStatus: func.isRequired,
    getFilter: func.isRequired,
    rowData: shape().isRequired,
  }

  state = {
    confirmShow: false,
  }

  showConfirm = () => {
    this.setState({ confirmShow: true })
  }
  handleCancel = () => {
    this.setState({ confirmShow: false })
  }
  handleConfirm = () => {
    const { rowData, getFilter, setUserStatus } = this.props
    setUserStatus(rowData.id, getFilter(), rowData.status === 1)
    this.setState({ confirmShow: false })
  }
  render() {
    const { rowData, localize } = this.props
    return (
      <Button.Group size="mini">
        {sF('UserDelete') &&
          <Button
            icon={rowData.status === 1 ? 'delete' : 'undo'}
            color={rowData.status === 1 ? 'red' : 'blue'}
            onClick={this.showConfirm}
          />
        }
        <Confirm
          open={this.state.confirmShow}
          onCancel={this.handleCancel}
          onConfirm={this.handleConfirm}
          content={`${localize(rowData.status === 1 ? 'DeleteUserMessage' : 'UndeleteUserMessage')} '${rowData.name}'?`}
          header={`${localize('AreYouSure')}?`}
        />
      </Button.Group>
    )
  }
}

export default ColumnActions

import React from 'react'
import { func, shape } from 'prop-types'
import { Button, Confirm } from 'semantic-ui-react'

import { checkSystemFunction as sF } from 'helpers/config'

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
    const msgKey = rowData.status === 1 ? 'DeleteUserMessage' : 'UndeleteUserMessage'
    return (
      <Button.Group size="mini">
        {sF('UserDelete') &&
          <Button
            icon={rowData.status === 1 ? 'trash' : 'undo'}
            color={rowData.status === 1 ? 'red' : 'green'}
            onClick={this.showConfirm}
          />
        }
        <Confirm
          open={this.state.confirmShow}
          onCancel={this.handleCancel}
          onConfirm={this.handleConfirm}
          content={`${localize(msgKey)} '${rowData.name}'?`}
          header={`${localize('AreYouSure')}?`}
        />
      </Button.Group>
    )
  }
}

export default ColumnActions

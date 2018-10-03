import React from 'react'
import { func, string, number } from 'prop-types'
import { Button, Confirm } from 'semantic-ui-react'

import { checkSystemFunction as sF } from 'helpers/config'

class ColumnActions extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    setUserStatus: func.isRequired,
    getFilter: func.isRequired,
    id: string.isRequired,
    status: number.isRequired,
    name: string.isRequired,
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
    const { id, status, getFilter, setUserStatus } = this.props
    setUserStatus(id, getFilter(), status === 2)
    this.setState({ confirmShow: false })
  }

  render() {
    const { status, name, localize } = this.props
    const msgKey = status === 2 ? 'DeleteUserMessage' : 'UndeleteUserMessage'
    return (
      status !== 0 && (
        <Button.Group size="mini">
          {sF('UserDelete') && (
            <Button
              icon={status === 2 ? 'trash' : 'undo'}
              color={status === 2 ? 'red' : 'green'}
              onClick={this.showConfirm}
            />
          )}
          <Confirm
            open={this.state.confirmShow}
            onCancel={this.handleCancel}
            onConfirm={this.handleConfirm}
            content={`${localize(msgKey)} '${name}'?`}
            header={`${localize('AreYouSure')}?`}
            confirmButton={localize('Ok')}
            cancelButton={localize('ButtonCancel')}
          />
        </Button.Group>
      )
    )
  }
}

export default ColumnActions

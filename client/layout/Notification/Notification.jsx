import React from 'react'
import { Confirm } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'

const Notification = ({ text, open, hideNotification, localize }) => (
  <Confirm
    open={open}
    content={localize(text)}
    onCancel={hideNotification}
    onConfirm={hideNotification}
  />
)

Notification.propTypes = {
  text: React.PropTypes.string.isRequired,
  open: React.PropTypes.bool.isRequired,
  hideNotification: React.PropTypes.func.isRequired,
  localize: React.PropTypes.func.isRequired,
}

export default wrapper(Notification)

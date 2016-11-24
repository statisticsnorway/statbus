import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

const SuccessMessage = ({ message }) => (
  <Message size="mini" icon positive>
    <Icon name="checkmark" />
    <Message.Header>{message}</Message.Header>
  </Message>
)

export default SuccessMessage

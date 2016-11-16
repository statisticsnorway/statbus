import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

const SuccessMessage = () => (
  <Message size="mini" icon positive>
    <Icon name="checkmark" />
    <Message.Header>Success</Message.Header>
  </Message>
)

export default SuccessMessage

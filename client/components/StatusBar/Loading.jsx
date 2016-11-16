import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

const LoadingMessage = () => (
  <Message size="mini" icon>
    <Icon name="spinner" loading />
    <Message.Content>
      <Message.Header>Loading</Message.Header>
    </Message.Content>
  </Message>
)

export default LoadingMessage

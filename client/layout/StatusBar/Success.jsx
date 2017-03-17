import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

import styles from './styles'

export default class Success extends React.Component {
  componentDidMount() {
    setTimeout(() => {
      this.props.dismiss()
    }, 3000)
  }
  render() {
    return (
      <Message
        onClick={this.props.dismiss}
        className={styles.success}
        content={this.props.message}
        icon="checkmark"
        size="mini"
        positive
      />
    )
  }
}

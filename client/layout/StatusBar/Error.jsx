import React from 'react'
import { Message } from 'semantic-ui-react'

import styles from './styles'

export default class Error extends React.Component {
  componentDidMount() {
    setTimeout(this.props.dismiss, 3000)
  }
  render() {
    return (
      <Message
        onClick={this.props.dismiss}
        className={styles.error}
        content={this.props.message}
        icon="minus circle"
        size="mini"
        negative
      />
    )
  }
}

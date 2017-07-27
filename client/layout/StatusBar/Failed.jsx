import React from 'react'
import PropTypes from 'prop-types'
import { Message } from 'semantic-ui-react'

import styles from './styles.pcss'

const Failed = ({ dismiss, message }) => (
  <Message
    onClick={dismiss}
    className={styles.error}
    content={message}
    icon="minus circle"
    size="mini"
    negative
  />
)

Failed.propTypes = {
  dismiss: PropTypes.func.isRequired,
  message: PropTypes.string,
}

Failed.defaultProps = {
  message: '',
}

export default Failed

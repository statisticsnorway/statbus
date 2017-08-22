import React from 'react'
import PropTypes from 'prop-types'
import { Message } from 'semantic-ui-react'

import styles from './styles.pcss'

const Success = ({ dismiss, message }) => (
  <Message
    onClick={dismiss}
    className={styles.success}
    content={message}
    icon="checkmark"
    size="mini"
    positive
  />
)

Success.propTypes = {
  dismiss: PropTypes.func.isRequired,
  message: PropTypes.string,
}

Success.defaultProps = {
  message: '',
}

export default Success

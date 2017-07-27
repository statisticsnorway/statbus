import React from 'react'
import PropTypes from 'prop-types'
import { Icon, Message } from 'semantic-ui-react'

import styles from './styles.pcss'

const Loading = ({ message }) => (
  <Message
    className={styles.loading}
    content={message}
    icon={<Icon name="spinner" loading />}
    size="mini"
  />
)

Loading.propTypes = {
  message: PropTypes.string,
}

Loading.defaultProps = {
  message: '',
}

export default Loading

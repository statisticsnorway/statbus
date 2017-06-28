import React from 'react'
import PropTypes from 'prop-types'
import { Link } from 'react-router'
import shouldUpdate from 'recompose/shouldUpdate'

import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'

const Footer = ({ localize }) => (
  <div className={styles['footer-root']}>
    <footer>
      <div className="ui inverted vertical footer segment">
        <div className="ui center aligned container">
          <div className="ui horizontal inverted small divided link list">
            <Link to="/about" className="item">{localize('About')}</Link>
          </div>
        </div>
      </div>
    </footer>
  </div>
)

Footer.propTypes = {
  localize: PropTypes.func.isRequired,
}

export const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang

export default wrapper(shouldUpdate(checkProps)(Footer))

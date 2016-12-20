import React from 'react'
import { Link } from 'react-router'

import { getText, wrapper } from 'helpers/locale'
import styles from './styles'

const Footer = ({ locale }) => (
  <div className={styles.root}>
    <footer>
      <div className="ui inverted vertical footer segment">
        <div className="ui center aligned container">
          <div className="ui horizontal inverted small divided link list">
            <Link to="/about" className="item">{getText(locale, 'About')}</Link>
          </div>
        </div>
      </div>
    </footer>
  </div>
)

Footer.propTypes = { locale: React.PropTypes.string.isRequired }

export default wrapper(Footer)

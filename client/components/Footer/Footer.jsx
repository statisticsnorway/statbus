import React from 'react'
import { Link } from 'react-router'

import { wrapper } from 'helpers/locale'
import styles from './styles'

const Footer = ({ localize }) => (
  <div className={styles.root}>
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

Footer.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Footer)

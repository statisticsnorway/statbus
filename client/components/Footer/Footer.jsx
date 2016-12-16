import React from 'react'
import { Link } from 'react-router'

import aL from '../../helpers/i18n'
import styles from './styles'

export default () => (
  <div className={styles.root}>
    <footer>
      <div className="ui inverted vertical footer segment">
        <div className="ui center aligned container">
          <div className="ui horizontal inverted small divided link list">
            <Link to="/about" className="item">{aL('About')}</Link>
          </div>
        </div>
      </div>
    </footer>
  </div>
)

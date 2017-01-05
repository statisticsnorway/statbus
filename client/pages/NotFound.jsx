import React from 'react'
import { Link } from 'react-router'

import { wrapper } from 'helpers/locale'

const NotFound = ({ localize }) => (
  <div>
    <span>{localize('PageNotFound')}!</span>
    <br />
    <Link to="/">{localize('BackToHome')}</Link>
  </div>
)

NotFound.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(NotFound)

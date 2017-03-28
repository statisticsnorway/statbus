import React from 'react'
import { Link } from 'react-router'

import { wrapper } from 'helpers/locale'

const NotFound = ({ localize }) => (
  <div>
    <h1>{localize('NotFoundMessage')}</h1>
    <br />
    <Link to="/">{localize('NotFoundBackToHome')}</Link>
  </div>
)

NotFound.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(NotFound)

import React from 'react'
import PropTypes from 'prop-types'
import { Link } from 'react-router'

import { withLocalize } from '/helpers/locale'

const NotFound = ({ localize }) => (
  <div>
    <h1>{localize('NotFoundMessage')}</h1>
    <br />
    <Link to="/">{localize('NotFoundBackToHome')}</Link>
  </div>
)

NotFound.propTypes = { localize: PropTypes.func.isRequired }

export default withLocalize(NotFound)

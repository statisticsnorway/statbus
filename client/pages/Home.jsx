import React from 'react'

import { wrapper } from 'helpers/locale'

const Home = ({ localize }) => (
  <span>{localize('HomeText')}</span>
)

Home.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Home)

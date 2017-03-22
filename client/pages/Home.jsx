import React from 'react'

import { wrapper } from 'helpers/locale'

const Home = props => <span>{props.localize('HomeText')}</span>

Home.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Home)

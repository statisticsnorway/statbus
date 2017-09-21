import React from 'react'
import PropTypes from 'prop-types'

import { withLocalize } from 'helpers/locale'

const Home = props => <span>{props.localize('HomeText')}</span>

Home.propTypes = { localize: PropTypes.func.isRequired }

export default withLocalize(Home)

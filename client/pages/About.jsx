import React from 'react'
import PropTypes from 'prop-types'

import { wrapper } from 'helpers/locale'

const AboutText = ({ localize }) => <span>{localize('AboutText')}</span>

AboutText.propTypes = { localize: PropTypes.func.isRequired }

export default wrapper(AboutText)

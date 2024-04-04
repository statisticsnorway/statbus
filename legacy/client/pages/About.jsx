import React from 'react'
import PropTypes from 'prop-types'

import { withLocalize } from '/helpers/locale'

const AboutText = ({ localize }) => <span>{localize('AboutText')}</span>

AboutText.propTypes = { localize: PropTypes.func.isRequired }

export default withLocalize(AboutText)

import React from 'react'

import { wrapper } from 'helpers/locale'

const AboutText = ({ localize }) => (
  <span>{localize('AboutText')}</span>
)

AboutText.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(AboutText)

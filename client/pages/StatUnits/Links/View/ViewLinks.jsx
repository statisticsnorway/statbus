import React from 'react'

import { wrapper } from 'helpers/locale'
import ViewFilter from './ViewFilter'

const { func } = React.PropTypes

class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
  }
  render() {
    const { localize } = this.props
    return (
      <ViewFilter
        localize={localize}
      />
    )
  }
}

export default wrapper(ViewLinks)

import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import ViewLinks from './ViewLinks.jsx'

export default connect(
  ({ viewLinks, locale }) => ({
    ...viewLinks,
    localize: getText(locale),
    locale,
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(ViewLinks)

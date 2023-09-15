import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import actions from './actions'
import ViewLinks from './ViewLinks'

export default connect(
  ({ viewLinks, locale }) => ({
    ...viewLinks,
    localize: getText(locale),
    locale,
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(ViewLinks)

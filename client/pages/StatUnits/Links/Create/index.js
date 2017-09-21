import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import CreateLink from './CreateLink'

export default connect(
  ({ editLinks, locale }, { router: { location: { query: params } } }) => ({
    ...editLinks,
    params,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(CreateLink)

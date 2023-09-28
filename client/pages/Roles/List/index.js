import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import actions from './actions'
import List from './List'

export default connect(
  ({ roles, locale }, { location: { query } }) => ({
    ...roles,
    query,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)

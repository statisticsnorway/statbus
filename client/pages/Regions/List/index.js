import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import actions from './actions'
import List from './List'

export default connect(
  ({ regions, locale }, { location: { query } }) => ({
    ...regions,
    query,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(List)

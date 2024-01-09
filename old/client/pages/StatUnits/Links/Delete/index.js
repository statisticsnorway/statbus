import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/helpers/locale'
import actions from './actions.js'
import DeleteLink from './DeleteLink.jsx'

export default connect(
  (
    { deleteLinks, locale },
    {
      router: {
        location: { query: params },
      },
    },
  ) => ({
    ...deleteLinks,
    params,
    localize: getText(locale),
  }),
  dispatch => bindActionCreators(actions, dispatch),
)(DeleteLink)

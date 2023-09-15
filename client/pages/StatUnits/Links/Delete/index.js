import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import actions from './actions'
import DeleteLink from './DeleteLink'

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

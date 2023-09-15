import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from '/client/helpers/locale'
import StatUnitViewPage from './StatUnitViewPage'
import viewActions from './actions'

const mapStateToProps = (
  {
    viewStatUnit: { statUnit, history, historyDetails, activeTab, orgLinks, errorMessage },
    locale,
  },
  { params: { id, type } },
) => ({
  id,
  type,
  unit: statUnit,
  history,
  historyDetails,
  orgLinks,
  activeTab,
  localize: getText(locale),
  errorMessage,
})

export default connect(mapStateToProps, dispatch => ({
  actions: bindActionCreators({ ...viewActions }, dispatch),
}))(StatUnitViewPage)

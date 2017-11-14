import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import StatUnitViewPage from './StatUnitViewPage'
import viewActions from './actions'

const mapStateToProps = (
  { viewStatUnit: { statUnit, history, historyDetails, activeTab, orgLinks }, locale },
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
})

export default connect(mapStateToProps, dispatch => ({
  actions: bindActionCreators({ ...viewActions }, dispatch),
}))(StatUnitViewPage)

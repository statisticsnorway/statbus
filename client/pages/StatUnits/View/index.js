import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import { getText } from 'helpers/locale'
import StatUnitViewPage from './StatUnitViewPage'
import viewActions from './actions'
import commonActions from '../actions'

const mapStateToProps = (
  {
    viewStatUnit: { statUnit, history, historyDetails, activeTab, orglinks },
    statUnitsCommon: { legalUnitsLookup, enterpriseUnitsLookup, enterpriseGroupsLookup },
    locale,
  },
  { params: { id, type },
}) => ({
  id,
  type,
  unit: statUnit,
  history,
  historyDetails,
  orglinks,
  legalUnitOptions: legalUnitsLookup.map(x => ({ value: x.id, text: x.name })),
  enterpriseUnitOptions: enterpriseUnitsLookup.map(x => ({ value: x.id, text: x.name })),
  enterpriseGroupOptions: enterpriseGroupsLookup.map(x => ({ value: x.id, text: x.name })),
  activeTab,
  localize: getText(locale),
})

export default connect(
  mapStateToProps,
  dispatch => ({
    actions: bindActionCreators({ ...viewActions, ...commonActions }, dispatch),
  }),
)(StatUnitViewPage)

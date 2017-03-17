import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import StatUnitViewPage from './StatUnitViewPage'
import * as viewActions from './actions'
import * as commonActions from '../actions'

const mapStateToProps = ({ viewStatUnit: { statUnit, activeTab },
  statUnitsCommon: { legalUnitsLookup, enterpriseUnitsLookup, enterpriseGroupsLookup } },
  { params: { id, type } }) => ({
    id,
    type,
    unit: statUnit,
    legalUnitOptions: legalUnitsLookup.map(x => ({ value: x.id, text: x.name })),
    enterpriseUnitOptions: enterpriseUnitsLookup.map(x => ({ value: x.id, text: x.name })),
    enterpriseGroupOptions: enterpriseGroupsLookup.map(x => ({ value: x.id, text: x.name })),
    activeTab,
  })

export default connect(mapStateToProps, dispatch => ({ actions: {
  ...bindActionCreators(viewActions, dispatch),
  ...bindActionCreators(commonActions, dispatch),
} }),
)(StatUnitViewPage)

import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import CreateStatUnitPage from './CreateStatUnitPage'
import * as createActions from './actions'
import * as commonActions from '../actions'

export default connect(
  ({ createStatUnit: { statUnit },
    statUnitsCommon: { legalUnitsLookup, enterpriseUnitsLookup, enterpriseGroupsLookup },
  }) => ({
    statUnit,
    legalUnitOptions: legalUnitsLookup.map(x => ({ value: x.id, text: x.name })),
    enterpriseUnitOptions: enterpriseUnitsLookup.map(x => ({ value: x.id, text: x.name })),
    enterpriseGroupOptions: enterpriseGroupsLookup.map(x => ({ value: x.id, text: x.name })),
  }),
  dispatch => ({
    actions: {
      ...bindActionCreators(createActions, dispatch),
      ...bindActionCreators(commonActions, dispatch),
    },
  }))(CreateStatUnitPage)

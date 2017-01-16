import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'

import * as editActions from './actions'
import * as commonActions from '../actions'
import EditForm from './EditForm'

export default connect(
  ({ editStatUnit: { statUnit },
    statUnitsCommon: { legalUnitsLookup, enterpriseUnitsLookup, enterpriseGroupsLookup } },
    { editForm, submitStatUnit, params }) => ({
      statUnit,
      editForm,
      submitStatUnit,
      id: params.id,
      type: params.type,
      legalUnitOptions: legalUnitsLookup.map(x => ({ value: x.id, text: x.name })),
      enterpriseUnitOptions: enterpriseUnitsLookup.map(x => ({ value: x.id, text: x.name })),
      enterpriseGroupOptions: enterpriseGroupsLookup.map(x => ({ value: x.id, text: x.name })),
    }),
  dispatch => ({
    actions: {
      ...bindActionCreators(editActions, dispatch),
      ...bindActionCreators(commonActions, dispatch),
    },
  }),
)(EditForm)

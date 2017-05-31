import { createReducer } from 'redux-act'

import simpleName from 'components/Search/nameCreator'
import * as actions from './actions'

const initialState = {
  role: undefined,
}

const editRole = createReducer(
  {
    [actions.fetchRoleSucceeded]: (state, data) => ({
      ...state,
      role: { ...data, region: { ...data.region, name: simpleName(data.region) } },
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      role: { ...state.role, [data.name]: data.value },
    }),
  },
  initialState,
)

export default {
  editRole,
}

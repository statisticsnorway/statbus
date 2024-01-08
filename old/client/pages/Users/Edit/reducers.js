import { createReducer } from 'redux-act'

import { distinctBy } from '/helpers/enumerable'
import * as actions from './actions.js'

const initialState = {
  user: undefined,
  activityTree: [],
}

const editUser = createReducer(
  {
    [actions.fetchUserSucceeded]: (state, data) => ({
      ...state,
      user: data,
    }),
    [actions.editForm]: (state, data) => ({
      ...state,
      user: { ...state.user, [data.name]: data.value },
    }),
    [actions.fetchUsersStarted]: state => ({
      ...state,
      user: undefined,
    }),
    [actions.fechRegionTreeSucceeded]: (state, data) => ({
      ...state,
      regionTree: data,
    }),
    [actions.fetchActivityTreeSucceded]: (state, data) => ({
      ...state,
      activityTree: distinctBy([...state.activityTree, ...data], x => x.id),
    }),
  },
  initialState,
)

export default {
  editUser,
}

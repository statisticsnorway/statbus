import { createReducer } from 'redux-act'

import { defaultPageSize } from '/helpers/paginate'
import * as actions from './actions.js'
import { submitUserFailed } from '../Edit/actions.js'
import { checkExistLoginSuccess } from '../Create/actions.js'

const users = createReducer(
  {
    [actions.fetchUsersSucceeded]: (state, data) => ({
      ...state,
      users: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
      filter: data.filter,
      isLoading: false,
      allRegions: data.allRegions,
    }),
    [actions.fetchUsersStarted]: (state, filter) => ({
      ...state,
      isLoading: true,
      filter,
    }),
    [actions.fetchUsersFailed]: state => ({
      ...state,
      users: [],
      isLoading: false,
    }),
    [submitUserFailed]: (state, error) => ({
      ...state,
      isLoading: false,
      loginError: error,
    }),
    [checkExistLoginSuccess]: (state, loginIsExist) => ({
      ...state,
      loginError: loginIsExist,
    }),
  },
  {
    isLoading: false,
    users: [],
    totalCount: 0,
    totalPages: 0,
    filter: {
      page: 1,
      pageSize: defaultPageSize,
      sortBy: 'status',
      sortAscending: undefined,
    },
    allRegions: {},
    loginError: null,
  },
)

export default {
  users,
}

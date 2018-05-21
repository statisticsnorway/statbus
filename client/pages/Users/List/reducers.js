import { createReducer } from 'redux-act'

import { defaultPageSize } from 'helpers/paginate'
import * as actions from './actions'

const users = createReducer(
  {
    [actions.fetchUsersSucceeded]: (state, data) => ({
      ...state,
      users: data.result,
      totalCount: data.totalCount,
      totalPages: data.totalPages,
      filter: data.filter,
      isLoading: false,
      partedRegions: data.partedRegions,
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
      sortAscending: false,
    },
    partedRegions: undefined,
  },
)

export default {
  users,
}

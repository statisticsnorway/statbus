import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from 'helpers/request'
import R from 'ramda'

export const updateFilter = createAction('update search dataSourceQueues form')
export const fetchDataStarted = createAction('fetch regions started')
export const fetchDataFailed = createAction('fetch DataSourceQueue failed')
export const fetchDataSuccessed = createAction('fetch DataSourceQueue successed')
export const clear = createAction('clear filter on DataSourceQueue')

export const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateFilter, dispatch)(query)
  const status = query.status === 'any' ? undefined : query.status
  R.pipe(push, dispatch)({ pathname, query: { ...query, status } })
}

const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/datasourcequeues',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchDataSuccessed({ ...resp, queryObj: queryParams }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchDataFailed(errors))
    },
  })

export default {
  fetchData,
  setQuery,
  updateFilter,
  clear,
}

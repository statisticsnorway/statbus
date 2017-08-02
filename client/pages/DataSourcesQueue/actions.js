import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import dispatchRequest from 'helpers/request'
import R from 'ramda'

const updateFilter = createAction('update search dataSourceQueues form')
const fetchDataStarted = createAction('fetch regions started')
const fetchDataFailed = createAction('fetch DataSourceQueue failed')
const fetchDataSucceeded = createAction('fetch DataSourceQueue successed')
const clear = createAction('clear filter on DataSourceQueue')

const setQuery = pathname => query => (dispatch) => {
  R.pipe(updateFilter, dispatch)(query)
  const status = query.status === 'any' ? undefined : query.status
  R.pipe(push, dispatch)({ pathname, query: { ...query, status } })
}

const fetchData = queryParams =>
  dispatchRequest({
    url: '/api/datasourcequeues',
    queryParams,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchDataSucceeded({ ...resp, queryObj: queryParams }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchDataFailed(errors))
    },
  })

export const list = {
  fetchData,
  setQuery,
  updateFilter,
  clear,
}

export default {
  updateFilter,
  fetchDataStarted,
  fetchDataFailed,
  fetchDataSucceeded,
  clear,
  setQuery,
}

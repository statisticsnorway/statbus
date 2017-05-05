import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'

import dispatchRequest from 'helpers/request'

const updateFilter = createAction('update data sources search form')
const setQuery = pathname => query => (dispatch) => {
  pipe(updateFilter, dispatch)(query)
  pipe(push, dispatch)({ pathname, query })
}

const fetchDataSourcesSucceeded = createAction('fetched data sources')
export const fetchDataSources = queryParams => dispatchRequest({
  queryParams,
  onSuccess: (dispatch, response) => {
    const { page, pageSize, ...formData } = queryParams
    dispatch(updateFilter(formData))
    dispatch(fetchDataSourcesSucceeded(response))
  },
})

const fetchColumnsSucceeded = createAction('fetched columns')
const fetchColumns = () => dispatchRequest({
  url: '/api/accessattributes/dataattributes',
  onSuccess: (dispatch, response) =>
    dispatch(fetchColumnsSucceeded(response)),
})

const createDataSource = data => dispatchRequest({
  url: '/api/datasources',
  method: 'post',
  body: data,
  onSuccess: dispatch =>
    dispatch(push('/datasources')),
})

export const search = {
  setQuery,
  updateFilter,
}

export const create = {
  fetchColumns,
  submitData: createDataSource,
}

export default {
  updateFilter,
  fetchColumnsSucceeded,
  fetchDataSourcesSucceeded,
}

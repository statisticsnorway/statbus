import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

const fetchDataSourcesSucceeded = createAction('fetched data sources')
const fetchDataSources = queryParams => dispatchRequest({
  queryParams,
  onSuccess: (dispatch, response) =>
    dispatch(fetchDataSourcesSucceeded(response)),
})

const fetchColumnsSucceeded = createAction('fetched columns')
const fetchColumns = () => dispatchRequest({
  url: 'api/accessattributes/dataattributes',
  onSuccess: (dispatch, response) =>
    dispatch(fetchColumnsSucceeded(response)),
})

const createDataSource = data => dispatchRequest({
  method: 'post',
  body: data,
  onSuccess: (dispatch) => {
    dispatch(push('/datasources'))
  },
})

export const list = {
  fetchData: fetchDataSources,
}

export const create = {
  fetchColumns,
  submitData: createDataSource,
}

export default {
  fetchColumnsSucceeded,
  fetchDataSourcesSucceeded,
}

import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'

import dispatchRequest from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const clear = createAction('clear filter on DataSources')

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

const fetchDataSourcesListSucceeded = createAction('fetched data sources list')
export const fetchDataSourcesList = () => dispatchRequest({
  url: '/api/datasources',
  method: 'get',
  onSuccess: (dispatch, response) => {
    dispatch(fetchDataSourcesListSucceeded(response))
  },
})

const uploadFileSucceeded = createAction('upload file')
const uploadFileError = createAction('upload file error')
export const uploadFile = (body, callBack) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  const xhr = new XMLHttpRequest()
  const onOk = (response) => {
    dispatch(uploadFileSucceeded(response))
    callBack()
    dispatch(rqstActions.succeeded())
    dispatch(rqstActions.dismiss(startedId))
  }
  const onErr = (err) => {
    dispatch(uploadFileError(err))
    callBack()
    dispatch(rqstActions.failed(err))
    dispatch(rqstActions.dismiss(startedId))
  }
  xhr.open('post', '/api/DataSourceQueues', true)
  xhr.onload = onOk
  xhr.onerror = onErr
  xhr.send(body)
}

const fetchColumnsSucceeded = createAction('fetched columns')
const fetchColumns = () => dispatchRequest({
  url: '/api/datasources/MappingProperties',
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
  fetchDataSourcesListSucceeded,
  uploadFileSucceeded,
  uploadFileError,
}

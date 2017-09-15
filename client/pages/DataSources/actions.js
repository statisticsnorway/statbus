import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'

import { nullsToUndefined } from 'helpers/schema'
import dispatchRequest from 'helpers/request'
import { navigateBack, request } from 'helpers/actionCreators'
import { schema, transformMapping } from './model'

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
export const uploadFile = (body, callback) => (dispatch) => {
  const startedAction = request.started()
  const startedId = startedAction.id
  const xhr = new XMLHttpRequest()
  xhr.onload = (response) => {
    dispatch(uploadFileSucceeded(response))
    callback()
    dispatch(request.succeeded())
    dispatch(request.dismiss(startedId))
  }
  xhr.onerror = (error) => {
    dispatch(uploadFileError(error))
    callback()
    dispatch(request.failed(error))
    dispatch(request.dismiss(startedId))
  }
  xhr.open('post', '/api/datasourcesqueue', true)
  xhr.send(body)
}

const fetchColumnsSucceeded = createAction('fetched columns')
const fetchColumns = () => dispatchRequest({
  url: '/api/datasources/MappingProperties',
  onSuccess: (dispatch, response) =>
    dispatch(fetchColumnsSucceeded(response)),
})

const createDataSource = (data, callbacks) => dispatchRequest({
  url: '/api/datasources',
  method: 'post',
  body: transformMapping(data),
  onSuccess: dispatch =>
    dispatch(push('/datasources')),
})

const fetchDataSourceSucceeded = createAction('fetched datasource')

const cast = resp => schema.cast(nullsToUndefined(resp))
const fetchDataSource = id => dispatchRequest({
  url: `api/datasources/${id}`,
  onSuccess: (dispatch, response) =>
    pipe(cast, fetchDataSourceSucceeded, dispatch)(response),
})

const editDataSource = id => (data, callbacks) => dispatchRequest({
  url: `/api/datasources/${id}`,
  method: 'put',
  body: transformMapping(data),
  onSuccess: dispatch =>
    dispatch(push('/datasources')),
})

export const deleteDataSource = id => dispatchRequest({
  url: `/api/datasources/${id}`,
  method: 'delete',
  onSuccess: () => {
    window.location.reload()
  },
})

export const search = {
  setQuery,
  updateFilter,
}

export const create = {
  fetchColumns,
  submitData: createDataSource,
  navigateBack,
}

export const edit = {
  fetchDataSource,
  fetchColumns,
  submitData: editDataSource,
  navigateBack,
}

export default {
  updateFilter,
  fetchColumnsSucceeded,
  fetchDataSourcesSucceeded,
  fetchDataSourcesListSucceeded,
  fetchDataSourceSucceeded,
  uploadFileSucceeded,
  uploadFileError,
}

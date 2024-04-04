import { createAction } from 'redux-act'
import { push } from 'react-router-redux'
import { pipe } from 'ramda'
import { nullsToUndefined } from '/helpers/validation'
import dispatchRequest from '/helpers/request'
import { navigateBack, request } from '/helpers/actionCreators'
import { createSchema, transformMapping } from './model.js'
import replaceComplexEntitiesForDataSourceTemplate from './replaceComplexEntitiesForDataSourceTemplate.js'

export const clear = createAction('clear filter on DataSources')
export const fetchError = createAction('handle error response')

const updateFilter = createAction('update data sources search form')
const setQuery = pathname => query => (dispatch) => {
  pipe(updateFilter, dispatch)(query)
  pipe(push, dispatch)({ pathname, query })
}

const fetchDataSourcesSucceeded = createAction('fetched data sources')
export const fetchDataSources = queryParams =>
  dispatchRequest({
    queryParams,
    onSuccess: (dispatch, response) => {
      const { page, pageSize, ...formData } = queryParams
      dispatch(updateFilter(formData))
      dispatch(fetchDataSourcesSucceeded(response))
    },
  })

const fetchDataSourcesListSucceeded = createAction('fetched data sources list')
export const fetchDataSourcesList = () =>
  dispatchRequest({
    queryParams: { getAll: true },
    url: '/api/datasources',
    method: 'get',
    onSuccess: (dispatch, response) => dispatch(fetchDataSourcesListSucceeded(response)),
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
const fetchColumns = () =>
  dispatchRequest({
    url: '/api/datasources/MappingProperties',
    onSuccess: (dispatch, response) =>
      pipe(replaceComplexEntitiesForDataSourceTemplate, fetchColumnsSucceeded, dispatch)(response),
  })

const createDataSource = (data, formikBag) => {
  const filteredData = { ...data }

  // eslint-disable-next-line prefer-const
  let OriginalCsvAttributes = []

  const variablesMapping = [...data.variablesMapping]

  const attributesToCheck = []
  const leftItem = 0

  variablesMapping.forEach((item, itemIndex) => {
    // eslint-disable-next-line prefer-destructuring
    OriginalCsvAttributes[itemIndex] = item[0]
  })

  variablesMapping.forEach((item, index) => {
    attributesToCheck[index] = item[leftItem]
  })

  filteredData.variablesMapping = variablesMapping
  filteredData.attributesToCheck = attributesToCheck

  return dispatchRequest({
    url: '/api/datasources',
    method: 'post',
    body: transformMapping({ OriginalCsvAttributes, ...filteredData }),
    onStart: () => formikBag.started(),
    onSuccess: (dispatch) => {
      dispatch(push('/datasources'))
    },
    onFail: (_, errors) => formikBag.failed(errors),
  })
}

const fetchDataSourceSucceeded = createAction('fetched datasource')

const fetchDataSource = (id, columns) =>
  dispatchRequest({
    url: `api/datasources/${id}`,
    onSuccess: (dispatch, response) =>
      pipe(
        nullsToUndefined,
        x => createSchema(columns).cast(x),
        fetchDataSourceSucceeded,
        dispatch,
      )(response),
    onFail: (dispatch, errors) => {
      dispatch(fetchError(errors))
    },
  })

const editDataSource = id => (data, formikBag) => {
  const filteredData = { ...data }

  // eslint-disable-next-line prefer-const
  let OriginalCsvAttributes = []

  const variablesMapping = [...data.variablesMapping]

  const attributesToCheck = []
  const leftItem = 0

  variablesMapping.forEach((item, itemIndex) => {
    // eslint-disable-next-line prefer-destructuring
    OriginalCsvAttributes[itemIndex] = item[0]
  })

  variablesMapping.forEach((item, index) => {
    attributesToCheck[index] = item[leftItem]
  })

  filteredData.variablesMapping = variablesMapping
  filteredData.attributesToCheck = attributesToCheck

  return dispatchRequest({
    url: `/api/datasources/${id}`,
    method: 'put',
    body: transformMapping({ OriginalCsvAttributes, ...filteredData }),
    onStart: () => formikBag.started(),
    onSuccess: dispatch => dispatch(push('/datasources')),
    onFail: (_, errors) => formikBag.failed(errors),
  })
}

const deleteDataSourceSuccessed = createAction('delete data source sucessed')
export const deleteDataSource = id =>
  dispatchRequest({
    url: `/api/datasources/${id}`,
    method: 'delete',
    onSuccess: dispatch => dispatch(deleteDataSourceSuccessed({ id })),
    onFail: (dispatch, errors) => dispatch(fetchError(errors)),
  })

export const search = {
  setQuery,
  updateFilter,
}

export const create = {
  fetchColumns,
  onSubmit: createDataSource,
  onCancel: navigateBack,
}

export const edit = {
  fetchDataSource,
  fetchColumns,
  onSubmit: editDataSource,
  onCancel: navigateBack,
}

export default {
  updateFilter,
  fetchColumnsSucceeded,
  fetchDataSourcesSucceeded,
  fetchDataSourcesListSucceeded,
  fetchDataSourceSucceeded,
  deleteDataSourceSuccessed,
  uploadFileSucceeded,
  uploadFileError,
}

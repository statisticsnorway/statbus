import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchRegionsStarted = createAction('fetch regions started')
export const fetchRegionsFailed = createAction('fetch regions failed')
export const fetchRegionsSuccessed = createAction('fetch regions successed')

const fetchRegions = () =>
  dispatchRequest({
    onStart: dispatch => dispatch(fetchRegionsStarted()),
    onSuccess: (dispatch, resp) => dispatch(fetchRegionsSuccessed(resp)),
    onFail: (dispatch, errors) => dispatch(fetchRegionsFailed(errors)),
  })

export const deleteRegionsStarted = createAction('delete regions started')
export const deleteRegionsFailed = createAction('delete regions failed')
export const deleteRegionsSuccessed = createAction('delete regions successed')

const deleteRegion = id =>
  dispatchRequest({
    url: `/api/regions/${id}`,
    method: 'delete',
    onStart: dispatch => dispatch(deleteRegionsStarted()),
    onSuccess: dispatch => dispatch(deleteRegionsSuccessed(id)),
    onFail: (dispatch, errors) => dispatch(deleteRegionsFailed(errors)),
  })

export const editRegionsStarted = createAction('edit regions started')
export const editRegionsFailed = createAction('edit regions failed')
export const editRegionsSuccessed = createAction('edit regions successed')

const editRegion = (id, data) =>
  dispatchRequest({
    url: `/api/regions/${id}`,
    method: 'put',
    body: data,
    onStart: dispatch => dispatch(editRegionsStarted()),
    onSuccess: dispatch => dispatch(editRegionsSuccessed({ id, ...data })),
    onFail: (dispatch, errors) => dispatch(editRegionsFailed(errors)),
  })

export const regionsEditorAction = createAction('regions editor action')
const editRegionRow = id => (dispatch) => {
  dispatch(regionsEditorAction(id))
}

export const regionAddEditorAction = createAction('regions adding editor action')
const addRegionEditor = visible => (dispatch) => {
  dispatch(regionAddEditorAction(visible))
}

export const addRegionsStarted = createAction('add regions started')
export const addRegionsFailed = createAction('add regions failed')
export const addRegionsSuccessed = createAction('add regions successed')

const addRegion = data =>
  dispatchRequest({
    url: '/api/regions',
    method: 'post',
    body: data,
    onStart: dispatch => dispatch(addRegionsStarted()),
    onSuccess: (dispatch, resp) => dispatch(addRegionsSuccessed(resp)),
    onFail: (dispatch, errors) => dispatch(addRegionsFailed(errors)),
  })

export default {
  fetchRegions,
  deleteRegion,
  editRegion,
  editRegionRow,
  addRegionEditor,
  addRegion,
}

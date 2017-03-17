import { createAction } from 'redux-act'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchRegionsStarted = createAction('fetch regions started')
export const fetchRegionsFailed = createAction('fetch regions failed')
export const fetchRegionsSuccessed = createAction('fetch regions successed')

const fetchRegions = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  dispatch(fetchRegionsStarted())
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchRegionsSuccessed(resp))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(fetchRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(fetchRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export const deleteRegionsStarted = createAction('delete regions started')
export const deleteRegionsFailed = createAction('delete regions failed')
export const deleteRegionsSuccessed = createAction('delete regions successed')

const deleteRegion = id => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  dispatch(deleteRegionsStarted())
  rqst({
    url: `/api/regions/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteRegionsSuccessed(id))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(deleteRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(deleteRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export const editRegionsStarted = createAction('edit regions started')
export const editRegionsFailed = createAction('edit regions failed')
export const editRegionsSuccessed = createAction('edit regions successed')

const editRegion = (id, data) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  dispatch(editRegionsStarted())
  rqst({
    url: `/api/regions/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      dispatch(editRegionsSuccessed({ id, ...data }))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(editRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(editRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

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

const addRegion = data => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  dispatch(addRegionsStarted())
  rqst({
    url: '/api/regions',
    method: 'post',
    body: data,
    onSuccess: (resp) => {
      dispatch(addRegionsSuccessed(resp))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(addRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(addRegionsFailed(errors))
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export default {
  fetchRegions,
  deleteRegion,
  editRegion,
  editRegionRow,
  addRegionEditor,
  addRegion,
}

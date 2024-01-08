import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'
import { withRouter } from 'react-router'

import createSchemaFormHoc from '/components/createSchemaFormHoc'
import createStatUnitSchema from '/helpers/createStatUnitSchema'
import {
  createFieldsMeta,
  createModel,
  createValues,
  updateProperties,
} from '/helpers/modelProperties'
import { getText } from '/helpers/locale'
import { details as actions } from '../actions.js'

const withSchemaForm = createSchemaFormHoc(
  props => props.schema,
  props => props.values,
)

const withConnect = connect(
  () =>
    createSelector(
      [
        state => state.locale,
        state => state.analysis.details.logEntry.unitType,
        state => state.analysis.details.logEntry.errors,
        state => state.analysis.details.properties,
        state => state.analysis.details.permissions,
        state => state.analysis.details.logEntry.unitId,
      ],
      (locale, type, errors, properties, permissions, unitId) => {
        const schema = createStatUnitSchema(type, permissions, properties, unitId)
        let updatedProperties = updateProperties(
          schema.cast(createModel(permissions, properties)),
          properties,
        )
        updatedProperties = updatedProperties.map(obj => ({
          ...obj,
          error: errors[obj.name] !== undefined,
          errors: errors[obj.name] !== undefined ? errors[obj.name] : null,
        }))
        return {
          schema,
          values: createValues(updatedProperties),
          initialErrors: errors,
          permissions,
          updatedProperties,
          fieldsMeta: createFieldsMeta(type, updatedProperties),
          localize: getText(locale),
        }
      },
    ),
  (dispatch, props) =>
    bindActionCreators(
      {
        onSubmit: actions.submitDetails(props.logId, props.queueId),
        onCancel: actions.navigateBack,
      },
      dispatch,
    ),
)

export default pipe(withRouter, withSchemaForm, withConnect)

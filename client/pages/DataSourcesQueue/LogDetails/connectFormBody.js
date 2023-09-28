import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'

import createSchemaFormHoc from '/client/components/createSchemaFormHoc'
import createStatUnitSchema from '/client/helpers/createStatUnitSchema'
import {
  createFieldsMeta,
  createModel,
  createValues,
  updateProperties,
  updateValuesFrom,
} from '/client/helpers/modelProperties'
import { getText } from '/client/helpers/locale'
import { details as actions } from '../actions'

const getSchema = props => props.schema
const mapPropsToValues = props => props.values

const mapStateToProps = () =>
  createSelector(
    [
      state => state.locale,
      state => state.dataSourcesQueue.details.unit,
      state => state.dataSourcesQueue.details.type,
      state => state.dataSourcesQueue.details.info.errors,
      state => state.dataSourcesQueue.details.properties,
      state => state.dataSourcesQueue.details.permissions,
    ],
    (locale, unit, type, errors, properties, permissions) => {
      const schema = createStatUnitSchema(type, permissions, properties, unit.regId)
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
        values: updateValuesFrom(unit)(createValues(updatedProperties)),
        initialErrors: errors,
        unit,
        schema,
        permissions,
        fieldsMeta: createFieldsMeta(type, updatedProperties),
        localize: getText(locale),
      }
    },
  )

const mapDispatchToProps = (dispatch, props) =>
  bindActionCreators(
    {
      onSubmit: actions.submitLogEntry(props.logId, props.queueId),
      onCancel: actions.navigateBack,
    },
    dispatch,
  )

export default pipe(
  createSchemaFormHoc(getSchema, mapPropsToValues),
  connect(mapStateToProps, mapDispatchToProps),
)

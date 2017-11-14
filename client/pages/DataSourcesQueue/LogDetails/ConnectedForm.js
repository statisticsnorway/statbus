import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'

import createSchemaFormHoc from 'components/createSchemaFormHoc'
import FormBody from 'components/StatUnitFormBody'
import createStatUnitSchema from 'helpers/createStatUnitSchema'
import {
  createFieldsMeta,
  createModel,
  createValues,
  updateProperties,
  updateValuesFrom,
} from 'helpers/modelProperties'
import { getText } from 'helpers/locale'
import { details as actions } from '../actions'

const getSchema = props => props.schema
const mapPropsToValues = props => props.values

const mapStateToProps = () =>
  createSelector(
    [
      state => state.locale,
      state => state.dataSourcesQueue.details.unit,
      state => state.dataSourcesQueue.details.type,
      state => state.dataSourcesQueue.details.properties,
      state => state.dataSourcesQueue.details.dataAccess,
    ],
    (locale, unit, type, properties, dataAccess) => {
      const schema = createStatUnitSchema(type)
      const updatedProperties = updateProperties(
        schema.cast(createModel(dataAccess, properties)),
        properties,
      )
      return {
        unit,
        schema,
        dataAccess,
        values: updateValuesFrom(unit)(createValues(dataAccess, updatedProperties)),
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
)(FormBody)

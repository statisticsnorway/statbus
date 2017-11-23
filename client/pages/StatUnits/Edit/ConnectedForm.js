import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'

import createSchemaFormHoc from 'components/createSchemaFormHoc/'
import FormBody from 'components/StatUnitFormBody'
import withSpinnerUnless from 'components/withSpinnerUnless'
import createSchema from 'helpers/createStatUnitSchema'
import { getText } from 'helpers/locale'
import {
  createFieldsMeta,
  createModel,
  createValues,
  updateProperties,
} from 'helpers/modelProperties'
import { actionCreators } from './actions'

const getSchema = props => props.schema
const mapPropsToValues = props => createValues(props.dataAccess, props.updatedProperties)

const createMapStateToProps = () =>
  createSelector(
    [
      state => state.editStatUnit.dataAccess,
      state => state.editStatUnit.properties,
      state => state.locale,
      (_, props) => props.type,
      (_, props) => props.onSubmit,
    ],
    (dataAccess, properties, locale, type, onSubmit) => {
      if (properties === undefined || dataAccess === undefined) {
        return { spinner: true }
      }
      const schema = createSchema(type, dataAccess.permissions)
      const updatedProperties = updateProperties(
        schema.cast(createModel(dataAccess, properties)),
        properties,
      )
      return {
        schema,
        dataAccess,
        updatedProperties,
        fieldsMeta: createFieldsMeta(type, updatedProperties),
        onSubmit,
        localize: getText(locale),
      }
    },
  )

const mapDispatchToProps = dispatch =>
  bindActionCreators({ onCancel: actionCreators.navigateBack }, dispatch)

const assert = props => !props.spinner

const enhance = pipe(
  createSchemaFormHoc(getSchema, mapPropsToValues),
  withSpinnerUnless(assert),
  connect(createMapStateToProps, mapDispatchToProps),
)

export default enhance(FormBody)

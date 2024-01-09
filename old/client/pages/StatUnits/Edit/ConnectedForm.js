import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'

import createSchemaFormHoc from '/components/createSchemaFormHoc'
import FormBody from '/components/StatUnitFormBody'
import withSpinnerUnless from '/components/withSpinnerUnless'
import createSchema from '/helpers/createStatUnitSchema'
import { getText } from '/helpers/locale'
import {
  createFieldsMeta,
  createModel,
  createValues,
  updateProperties,
} from '/helpers/modelProperties'

const getSchema = props => props.schema
const mapPropsToValues = props => createValues(props.updatedProperties)

const createMapStateToProps = () =>
  createSelector(
    [
      state => state.editStatUnit.permissions,
      state => state.editStatUnit.properties,
      state => state.locale,
      (_, props) => props.type,
      (_, props) => props.onSubmit,
      (_, props) => props.regId,
    ],
    (permissions, properties, locale, type, onSubmit, regId) => {
      if (properties === undefined || permissions === undefined) {
        return { spinner: true }
      }
      const schema = createSchema(type, permissions, properties, regId)
      const updatedProperties = updateProperties(
        schema.cast(createModel(permissions, properties)),
        properties,
      )
      return {
        schema,
        permissions,
        updatedProperties,
        fieldsMeta: createFieldsMeta(type, updatedProperties),
        onSubmit,
        localize: getText(locale),
        locale,
      }
    },
  )

const mapDispatchToProps = (dispatch, ownProps) =>
  bindActionCreators({ onCancel: ownProps.goBack }, dispatch)

const assert = props => !props.spinner

const enhance = pipe(
  createSchemaFormHoc(getSchema, mapPropsToValues),
  withSpinnerUnless(assert),
  connect(createMapStateToProps, mapDispatchToProps),
)

export default enhance(FormBody)

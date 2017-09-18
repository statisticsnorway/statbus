import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'

import StatUnitForm from 'components/StatUnitForm'
import withSpinnerUnless from 'components/withSpinnerUnless'
import createSchema from 'helpers/createStatUnitSchema'
import { getText } from 'helpers/locale'
import { createModel, createFieldsMeta, updateProperties, createValues } from 'helpers/modelProperties'
import { actionCreators } from './actions'

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
      const schema = createSchema(type)
      const updatedProperties = updateProperties(
        schema.cast(createModel(dataAccess, properties)),
        properties,
      )
      return {
        values: createValues(dataAccess, updatedProperties),
        schema,
        fieldsMeta: createFieldsMeta(updatedProperties),
        dataAccess,
        localize: getText(locale),
        onSubmit,
      }
    },
  )

const { navigateBack: onCancel } = actionCreators
const mapDispatchToProps = dispatch => bindActionCreators({ onCancel }, dispatch)

const assert = props => !props.spinner

const enhance = pipe(
  withSpinnerUnless(assert),
  connect(createMapStateToProps, mapDispatchToProps),
)

export default enhance(StatUnitForm)

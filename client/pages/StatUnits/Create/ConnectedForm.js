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
  createModel, createFieldsMeta, updateProperties, createValues,
} from 'helpers/modelProperties'
import { stripNullableFields } from 'helpers/validation'
import { actionCreators } from './actions'

const SchemaForm = createSchemaFormHoc(props => createSchema(props.type))(FormBody)

const createMapStateToProps = () =>
  createSelector(
    [
      state => state.createStatUnit.dataAccess,
      state => state.createStatUnit.properties,
      state => state.locale,
      (_, props) => props.type,
    ],
    (dataAccess, properties, locale, type) => {
      if (properties === undefined || dataAccess === undefined) {
        return { spinner: true }
      }
      const updatedProperties = updateProperties(
        createSchema(type).cast(createModel(dataAccess, properties)),
        properties,
      )
      return {
        values: createValues(dataAccess, updatedProperties),
        fieldsMeta: createFieldsMeta(updatedProperties),
        type,
        dataAccess,
        localize: getText(locale),
      }
    },
  )

// TODO: should be configurable
const ensure = stripNullableFields(['foreignParticipationCountryId'])

const mapDispatchToProps = (dispatch, { type }) =>
  bindActionCreators(
    {
      onSubmit: (statUnit, formActions) =>
        actionCreators.submitStatUnit(type, ensure(statUnit), formActions),
      onCancel: actionCreators.navigateBack,
    },
    dispatch,
  )

const assert = props => !props.spinner

const enhance = pipe(
  withSpinnerUnless(assert),
  connect(createMapStateToProps, mapDispatchToProps),
)

export default enhance(SchemaForm)

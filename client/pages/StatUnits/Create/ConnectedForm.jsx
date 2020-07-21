import React from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'
import moment from 'moment'

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
import { getDate, toUtc } from 'helpers/dateHelper'
import { actionCreators } from './actions'

const getSchema = props => props.schema
const mapPropsToValues = props => createValues(props.updatedProperties)

const createMapStateToProps = () =>
  createSelector(
    [
      state => state.createStatUnit.permissions,
      state => state.createStatUnit.properties,
      state => state.locale,
      (_, props) => props.type,
    ],
    (permissions, properties, locale, type) => {
      if (properties === undefined || permissions === undefined) {
        return { spinner: true }
      }
      const schema = createSchema(type, permissions, properties, null)
      const updatedProperties = updateProperties(
        schema.cast(createModel(permissions, properties)),
        properties,
      )
      return {
        schema,
        permissions,
        updatedProperties,
        fieldsMeta: createFieldsMeta(type, updatedProperties),
        localize: getText(locale),
        locale,
      }
    },
  )

const mapDispatchToProps = (dispatch, { type }) =>
  bindActionCreators(
    {
      onSubmit: (statUnit, formActions) =>
        actionCreators.submitStatUnit(type, statUnit, formActions),
      onCancel: actionCreators.navigateBack,
    },
    dispatch,
  )

const assert = props => !props.spinner

const enhance = pipe(
  createSchemaFormHoc(getSchema, mapPropsToValues),
  withSpinnerUnless(assert),
  connect(
    createMapStateToProps,
    mapDispatchToProps,
  ),
)

export default enhance((props) => {
  const { values } = props
  const currentDate = moment(getDate(), 'YYYY-MM-DD')
  const lastYear = moment().format('YYYY') - 1
  if (values.taxRegId) {
    values.taxRegDate = values.taxRegDate || currentDate
  } else {
    values.taxRegDate = undefined
  }
  if (values.externalId) {
    values.externalIdDate = values.externalIdDate || currentDate
  } else {
    values.externalIdDate = undefined
  }
  if (values.turnover) {
    values.turnoverYear = values.turnoverYear || lastYear
    values.turnoverDate = values.turnoverDate || currentDate
  } else {
    values.turnoverYear = undefined
    values.turnoverDate = undefined
  }
  if (values.employees) {
    values.employeesYear = values.turnoverYear || lastYear
    values.employeesDate = values.turnoverDate || currentDate
  } else {
    values.employeesYear = undefined
    values.employeesDate = undefined
  }

  if (values.registrationReasonId) {
    values.registrationDate = values.registrationDate || currentDate
  } else {
    values.registrationDate = undefined
  }

  if (props.type === 1) {
    if (values.legalUnitId) {
      values.legalUnitIdDate = values.legalUnitIdDate || currentDate
    } else {
      values.legalUnitIdDate = undefined
    }
  }

  if (props.type === 2 && values.enterpriseUnitRegId) {
    if (values.enterpriseUnitRegId) {
      values.entRegIdDate = values.entRegIdDate || currentDate
    } else {
      values.entRegIdDate = undefined
    }
  }

  if (props.type === 3) {
    if (values.entGroupId) {
      values.entGroupIdDate = values.entGroupIdDate || currentDate
    } else {
      values.entGroupIdDate = undefined
    }
  }

  if (props.type === 4) {
    if (values.reorgTypeId) {
      values.registrationDate = values.registrationDate || currentDate
    } else {
      values.registrationDate = undefined
    }
    if (values.reorgTypeCode) {
      values.reorgDate = values.reorgDate || currentDate
    } else {
      values.reorgDate = undefined
    }

    if (values.registrationReasonId) {
      values.registrationDate = values.registrationDate || currentDate
    } else {
      values.registrationDate = undefined
    }

    if (values.reorgTypeId) {
      values.reorgDate = values.reorgDate || currentDate
    } else {
      values.reorgDate = undefined
    }
  }

  return <FormBody {...{ ...props }} />
})

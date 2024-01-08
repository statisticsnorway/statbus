import React, { useMemo, useEffect } from 'react'
import { bindActionCreators } from 'redux'
import { connect, useDispatch, useSelector } from 'react-redux'
import { createSelector } from 'reselect'
import { pipe } from 'ramda'
import moment from 'moment'

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
import { getDate, toUtc } from '/helpers/dateHelper'
import { actionCreators } from './actions.js'

const getSchema = props => props.schema
const mapPropsToValues = props => createValues(props.updatedProperties)

const StatUnitForm = (props) => {
  const { type, values } = props
  const dispatch = useDispatch()

  const permissions = useSelector(state => state.createStatUnit.permissions)
  const properties = useSelector(state => state.createStatUnit.properties)
  const locale = useSelector(state => state.locale)

  const currentDate = moment(getDate(), 'YYYY-MM-DD')
  const lastYear = moment().format('YYYY') - 1

  const schema = useMemo(() => createSchema(type, permissions, properties, null), [
    type,
    permissions,
    properties,
  ])

  const updatedProperties = useMemo(
    () => updateProperties(schema.cast(createModel(permissions, properties)), properties),
    [schema, permissions, properties],
  )

  const fieldsMeta = useMemo(() => createFieldsMeta(type, updatedProperties), [
    type,
    updatedProperties,
  ])

  const localize = key => getText(locale)(key)

  const handleSubmit = (statUnit, formActions) => {
    dispatch(actionCreators.submitStatUnit(type, statUnit, formActions))
  }

  const handleCancel = () => {
    dispatch(actionCreators.navigateBack())
  }

  useEffect(() => {
    if (!props.spinner) {
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
      if (type === 1) {
        if (values.legalUnitId) {
          values.legalUnitIdDate = values.legalUnitIdDate || currentDate
        } else {
          values.legalUnitIdDate = undefined
        }
      }
      if (type === 2 && values.enterpriseUnitRegId) {
        if (values.enterpriseUnitRegId) {
          values.entRegIdDate = values.entRegIdDate || currentDate
        } else {
          values.entRegIdDate = undefined
        }
      }
      if (type === 3) {
        if (values.entGroupId) {
          values.entGroupIdDate = values.entGroupIdDate || currentDate
        } else {
          values.entGroupIdDate = undefined
        }
      }
      if (type === 4) {
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
    }
  }, [values, currentDate, lastYear, type, props.spinner])

  return <FormBody {...{ ...props, schema, fieldsMeta, localize, handleSubmit, handleCancel }} />
}

const mapStateToProps = createSelector(
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
  connect(mapStateToProps, mapDispatchToProps),
)

export default enhance(StatUnitForm)

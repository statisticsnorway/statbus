import React from 'react'
import { Formik } from 'formik'

import { createModel, createFieldsMeta, updateProperties, createValues } from 'helpers/modelProperties'
import createSchema from 'helpers/createStatUnitSchema'
import { stripNullableFields } from 'helpers/schema'
import SubForm from './SubForm'

// TODO: should be configurable
const ensure = stripNullableFields([
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'foreignParticipationCountryId',
  'legalUnitId',
  'entGroupId',
])

const mapPropsToValues = props =>
  createValues(
    props.dataAccess,
    updateProperties(
      createSchema(props.type).cast(createModel(props.dataAccess, props.properties)),
      props.properties,
    ),
  )

const makeFieldsMeta = (schema, dataAccess, properties) =>
  createFieldsMeta(updateProperties(
    schema.cast(createModel(dataAccess, properties)),
    properties,
  ))

// =====================================
const withLifecycleLogs = require('recompose').lifecycle({
  componentDidMount: () => console.log('cDMo'),
  componentWillUnmount: () => console.log('cWUn'),
})
// =====================================

const SchemaFormFactory = ({
  type,
  properties,
  dataAccess,
  onSubmit,
  onCancel,
  localize,
  ...rest
}) => {
  // TODO: revise schema and values creation
  const validationSchema = createSchema(type)
  const withFormik = Formik({
    ...rest,
    mapPropsToValues,
    validationSchema,
    handleSubmit: (statUnit, formActions) =>
      onSubmit({ ...ensure(statUnit), type }, formActions),
  })
  const SchemaForm = withFormik(SubForm)
  return (
    <SchemaForm
      type={type}
      properties={properties}
      dataAccess={dataAccess}
      fieldsMeta={makeFieldsMeta(validationSchema, dataAccess, properties)}
      handleCancel={onCancel}
      localize={localize}
    />
  )
}

export default SchemaFormFactory

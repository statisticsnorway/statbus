import React from 'react'
import { Formik } from 'formik'

import { createModel, createFieldsMeta, updateProperties } from 'helpers/modelProperties'
import createSchema from 'helpers/createStatUnitSchema'
import { stripNullableFields } from 'helpers/schema'
import Form from './Form'

// TODO: should be configurable
const stripStatUnitFields = stripNullableFields([
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'foreignParticipationCountryId',
  'legalUnitId',
  'entGroupId',
])

export default ({
  type,
  properties,
  dataAccess,
  onSubmit,
  onCancel,
  ...rest
}) => {
  // TODO: revise schema and values creation
  const schema = createSchema(type)
  const castedProperties = updateProperties(
    schema.cast(createModel(dataAccess, properties)),
    properties,
  )
  const options = {
    displayName: 'StatUnitSchemaForm',
    mapPropsToValues: props => createModel(
      props.dataAccess,
      updateProperties(
        createSchema(props.type).cast(createModel(props.dataAccess, props.properties)),
        props.properties,
      ),
    ),
    validationSchema: schema,
    fieldsMeta: createFieldsMeta(castedProperties),
    handleSubmit: (statUnit, formActions) => {
      onSubmit(
        { ...stripStatUnitFields(statUnit), type },
        formActions,
      )
    },
    handleCancel: onCancel,
    ...rest,
  }
  const SchemaForm = Formik(options)(Form)
  return <SchemaForm type={type} properties={properties} dataAccess={dataAccess} {...rest} />
}

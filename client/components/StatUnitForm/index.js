import React from 'react'
import { Formik } from 'formik'

import { createModel, createFieldsMeta, updateProperties, createValues } from 'helpers/modelProperties'
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
  localize,
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
    mapPropsToValues: props => createValues(
      props.dataAccess,
      updateProperties(
        createSchema(props.type).cast(createModel(props.dataAccess, props.properties)),
        props.properties,
      ),
    ),
    validationSchema: schema,
    handleSubmit: (statUnit, formActions) => {
      onSubmit(
        { ...stripStatUnitFields(statUnit), type },
        formActions,
      )
    },
    ...rest,
  }
  const SchemaForm = Formik(options)(Form)
  return (
    <SchemaForm
      type={type}
      properties={properties}
      dataAccess={dataAccess}
      fieldsMeta={createFieldsMeta(castedProperties)}
      handleCancel={onCancel}
      localize={localize}
    />
  )
}

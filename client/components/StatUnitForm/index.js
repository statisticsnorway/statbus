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
  const schema = createSchema(type)
  // TODO: revise createModel calls
  const castedProperties = updateProperties(
    schema.cast(createModel(dataAccess, properties)),
    properties,
  )
  const options = {
    displayName: 'StatUnitSchemaForm',
    values: createModel(dataAccess, castedProperties),
    mapPropsToValues: props => ({ ...props.values }),
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
  return Formik(options)(Form)
}

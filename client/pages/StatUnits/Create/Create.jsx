import React from 'react'
import { Select } from 'semantic-ui-react'
import PropTypes from 'prop-types'

import StatUnitForm from 'components/StatUnitForm'
import { statUnitTypes } from 'helpers/enums'
import { createModel } from 'helpers/modelProperties'
import { stripNullableFields } from 'helpers/schema'
import styles from './styles.pcss'

// TODO: should be configurable
const stripStatUnitFields = stripNullableFields([
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'foreignParticipationCountryId',
  'legalUnitId',
  'entGroupId',
])

const CreateStatUnitPage = ({
  type, dataAccess, properties, schema, errors,
  navigateBack, submitStatUnit, changeType, localize,
}) => {
  const handleTypeChange = (_, { value }) => {
    if (type !== value) changeType(value)
  }

  const handleSubmit = (statUnit, { setSubmitting, setErrors }) => {
    const processedStatUnit = stripStatUnitFields(statUnit)
    const data = { ...processedStatUnit, type }
    submitStatUnit(data, { setSubmitting, setErrors })
  }

  const typeOptions = [...statUnitTypes].map(kv => ({
    value: kv[0],
    text: localize(kv[1]),
  }))

  return (
    <div className={styles.root}>
      <Select
        value={type}
        onChange={handleTypeChange}
        options={typeOptions}
      />
      <br />
      <StatUnitForm
        properties={properties}
        dataAccess={dataAccess}
        mapPropsToValues={p => createModel(p.dataAccess, p.properties)}
        validationSchema={schema}
        errors={errors}
        handleSubmit={handleSubmit}
        handleCancel={navigateBack}
      />
    </div>
  )
}

const { arrayOf, string, func, number, shape } = PropTypes
CreateStatUnitPage.propTypes = {
  type: number.isRequired,
  dataAccess: arrayOf(string).isRequired,
  properties: arrayOf(shape({})).isRequired,
  schema: shape({}).isRequired,
  errors: shape({}),
  navigateBack: func.isRequired,
  changeType: func.isRequired,
  submitStatUnit: func.isRequired,
  localize: func.isRequired,
}

CreateStatUnitPage.defaultProps = {
  errors: undefined,
}

export default CreateStatUnitPage

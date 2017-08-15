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

const CreateStatUnitPage = (
  { type, statUnit, schema, navigateBack, submitStatUnit, changeType, localize },
) => {
  const handleTypeChange = (_, { value }) => {
    if (type !== value) {
      changeType(value)
    }
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
        statUnit={statUnit}
        validationSchema={schema}
        mapPropsToValues={p => createModel(p.statUnit)}
        handleSubmit={handleSubmit}
        handleCancel={navigateBack}
      />
    </div>
  )
}

const { func, number, shape } = PropTypes
CreateStatUnitPage.propTypes = {
  type: number.isRequired,
  statUnit: shape({}).isRequired,
  schema: shape({}).isRequired,
  navigateBack: func.isRequired,
  changeType: func.isRequired,
  submitStatUnit: func.isRequired,
  localize: func.isRequired,
}

export default CreateStatUnitPage

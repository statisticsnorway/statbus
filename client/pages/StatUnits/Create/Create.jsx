import React from 'react'
import PropTypes from 'prop-types'
import { Select } from 'semantic-ui-react'

import StatUnitForm from 'components/StatUnitForm'
import { statUnitTypes } from 'helpers/enums'
import styles from './styles.pcss'

const CreateStatUnitPage = ({
  type, dataAccess, properties, isSubmitting,
  navigateBack, submitStatUnit, changeType, localize,
}) => {
  const handleTypeChange = (_, { value }) => {
    if (type !== value) changeType(value)
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
        disabled={isSubmitting}
      />
      <br />
      <StatUnitForm
        type={type}
        properties={properties}
        dataAccess={dataAccess}
        onSubmit={submitStatUnit}
        onCancel={navigateBack}
        localize={localize}
      />
    </div>
  )
}

const { arrayOf, string, func, number, shape, bool } = PropTypes
CreateStatUnitPage.propTypes = {
  type: number.isRequired,
  dataAccess: arrayOf(string).isRequired,
  properties: arrayOf(shape({})).isRequired,
  isSubmitting: bool.isRequired,
  navigateBack: func.isRequired,
  changeType: func.isRequired,
  submitStatUnit: func.isRequired,
  localize: func.isRequired,
}

CreateStatUnitPage.defaultProps = {
  errors: undefined,
}

export default CreateStatUnitPage

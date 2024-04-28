import React from 'react'
import PropTypes from 'prop-types'
import { Select } from 'semantic-ui-react'

import { statUnitTypes } from '/helpers/enums'
import ConnectedForm from './ConnectedForm.jsx'
import styles from './styles.scss'

const CreateStatUnitPage = ({ type, isSubmitting, changeType, localize }) => {
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
      <ConnectedForm type={type} showSummary />
    </div>
  )
}

const { func, number, bool } = PropTypes
CreateStatUnitPage.propTypes = {
  type: number.isRequired,
  isSubmitting: bool.isRequired,
  changeType: func.isRequired,
  localize: func.isRequired,
}

export default CreateStatUnitPage

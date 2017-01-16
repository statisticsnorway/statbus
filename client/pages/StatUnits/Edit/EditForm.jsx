import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import EditStatUnit from './EditStatUnit'
import EditEnterpriseUnit from './EditEnterpriseUnit'
import EditLocalUnit from './EditLocalUnit'
import EditLegalUnit from './EditLegalUnit'
import EditEnterpriseGroup from './EditEnterpriseGroup'
import { format } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class EditForm extends React.Component {
  componentDidMount() {
    const { id, type,
      actions: {
        fetchStatUnit,
        fetchLocallUnitsLookup,
        fetchLegalUnitsLookup,
        fetchEnterpriseUnitsLookup,
        fetchEnterpriseGroupsLookup,
      },
    } = this.props
    fetchStatUnit(type, id)
      .then(() => fetchLocallUnitsLookup())
      .then(() => fetchLegalUnitsLookup())
      .then(() => fetchEnterpriseUnitsLookup())
      .then(() => fetchEnterpriseGroupsLookup())
  }

  render() {
    const { statUnit, actions: { editForm, submitStatUnit }, localize,
      legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions } = this.props

    const handleSubmit = (e) => {
      e.preventDefault()
      submitStatUnit(statUnit)
    }
    const handleEdit = propName => e => editForm({ propName, value: e.target.value })
    const handleDateEdit = propName => ({ _d: date }) =>
                                    editForm({ propName, value: format(date) })
    const handleSelectEdit = (e, { name, value }) => editForm({ propName: name, value })

    return (
      <div className={styles.edit}>
        <Form className={styles.form} onSubmit={handleSubmit}>
          {statUnit.type !== 4 &&
          <EditStatUnit
            {...{ statUnit, handleEdit, handleDateEdit, handleSelectEdit }}
          />}
          {statUnit.type === 1 &&
          <EditLocalUnit
            {...{
              statUnit,
              handleEdit,
              handleDateEdit,
              legalUnitOptions,
              enterpriseUnitOptions,
              handleSelectEdit,
            }}
          />}
          {statUnit.type === 2 &&
          <EditLegalUnit
            {...{ statUnit, handleEdit, handleDateEdit, enterpriseUnitOptions, handleSelectEdit }}
          />}
          {statUnit.type === 3 &&
          <EditEnterpriseUnit
            {...{ statUnit, handleEdit, handleDateEdit, enterpriseGroupOptions, handleSelectEdit }}
          />}
          {statUnit.type === 4 &&
          <EditEnterpriseGroup
            {...{ statUnit, handleEdit, handleDateEdit, handleSelectEdit }}
          />}
          <br />
          <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
        </Form>
      </div>
    )
  }
}

const { func, string, number, shape } = React.PropTypes

EditForm.propTypes = {
  actions: shape({
    editForm: func.isRequired,
    submitStatUnit: func.isRequired,
    fetchStatUnit: func.isRequired,
  }),
  id: string.isRequired,
  type: number.isRequired,
}


EditForm.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(EditForm)

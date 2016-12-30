import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import EditStatUnit from './EditStatUnit'
import EditEnterpriseUnit from './EditEnterpriseUnit'
import EditLocalUnit from './EditLocalUnit'
import EditLegalUnit from './EditLegalUnit'
import { format } from 'helpers/dateHelper'

class EditForm extends React.Component {
  componentDidMount() {
    this.props.fetchStatUnit(this.props.id)
  }

  render() {
    const { statUnit, editForm, submitStatUnit } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitStatUnit(statUnit)
    }
    const handleEdit = propName => e => editForm({ propName, value: e.target.value })
    const handleDateEdit = propName => ({ _d: date }) =>
                                    editForm({ propName, value: format(date) })
    return (
      <Form onSubmit={handleSubmit}>
        <EditStatUnit {...{ statUnit, handleEdit, handleDateEdit }} />
        {statUnit.type === 1 && <EditLocalUnit {...{ statUnit, handleEdit, handleDateEdit }} />}
        {statUnit.type === 2 && <EditLegalUnit {...{ statUnit, handleEdit, handleDateEdit }} />}
        {statUnit.type === 3 &&
          <EditEnterpriseUnit
            {...{ statUnit, handleEdit, handleDateEdit }}
          />}
        <Button>submit</Button>
      </Form>
    )
  }
}

const { func, string } = React.PropTypes

EditForm.propTypes = {
  editForm: func.isRequired,
  submitStatUnit: func.isRequired,
  fetchStatUnit: func.isRequired,
  id: string.isRequired,
}

export default EditForm

import React from 'react'

import CreateForm from './CreateForm'

class CreateStatUnitPage extends React.Component {
  componentDidMount() {
    const { actions } = this.props
    actions.fetchLocallUnitsLookup()
      .then(() => actions.fetchLegalUnitsLookup())
      .then(() => actions.fetchEnterpriseUnitsLookup())
      .then(() => actions.fetchEnterpriseGroupsLookup())
  }
  render() {
    const { statUnit, actions: { editForm, submitStatUnit },
      legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions } = this.props
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      submitStatUnit({ ...formData })
    }
    return (
      <CreateForm
        {...{
          statUnit,
          editForm,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
          handleSubmit
        }}
      />
    )
  }
}

const { shape, func } = React.PropTypes

CreateStatUnitPage.propTypes = {
  actions: shape({
    editForm: func.isRequired,
    submitStatUnit: func.isRequired,
    fetchStatUnit: func.isRequired,
  }),
}

export default CreateStatUnitPage

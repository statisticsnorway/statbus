import React from 'react'

import CreateForm from './CreateForm'
import schema from '../schema'

class CreateStatUnitPage extends React.Component {

  componentDidMount() {
    const { actions, type } = this.props
    actions.getModel(type)
  }

  componentWillReceiveProps(newProps) {
    const { actions, type } = this.props
    const { type: newType } = newProps
    if (newType != type) {
      actions.getModel(newType)
    }
  }

  handleSubmit = (e, { formData }) => {
    e.preventDefault()
    const { type, actions: { submitStatUnit, setErrors } } = this.props
    const data = Object.entries(formData)
      .reduce(
        (prev, [k, v]) => ({ ...prev, [k]: v === '' ? null : v }),
        { type },
      )

    schema
      .validate(formData, { abortEarly: false })
      .then(() => submitStatUnit(data))
      .catch(({ inner }) => {
        const errors = inner.reduce(
          (prev, cur) => ({ ...prev, [cur.path]: cur.errors }),
          {},
        )
        setErrors(errors)
      })
  }

  render() {
    const { actions: { changeType }, statUnitModel, type, errors } = this.props
    return (
      <CreateForm
        {...{
          statUnitModel,
          changeType,
          type,
          errors,
          handleSubmit: this.handleSubmit,
        }}
      />
    )
  }
}

const { shape, func } = React.PropTypes

CreateStatUnitPage.propTypes = {
  actions: shape({
    changeType: func.isRequired,
    submitStatUnit: func.isRequired,
  }).isRequired,
}

export default CreateStatUnitPage

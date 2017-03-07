import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import SchemaForm from 'components/Form'
import getField from 'components/getField'
import { wrapper } from 'helpers/locale'
import { getModel } from 'helpers/modelProperties'
import styles from './styles.pcss'
import statUnitSchema from '../schema'

const { shape, func, number } = React.PropTypes

class CreateStatUnitPage extends React.Component {

  static propTypes = {
    actions: shape({
      changeType: func.isRequired,
      submitStatUnit: func.isRequired,
    }).isRequired,
    type: number.isRequired,
    localize: func.isRequired,
  }

  componentDidMount() {
    const { actions, type } = this.props
    actions.getModel(type)
  }

  componentWillReceiveProps(newProps) {
    const { actions, type } = this.props
    const { type: newType } = newProps
    if (newType !== type) {
      actions.getModel(newType)
    }
  }

  handleOnChange = (e, { name, value }) => {
    this.props.actions.editForm({ name, value })
  }

  handleSubmit = (e, { formData }) => {
    e.preventDefault()
    const { type, actions: { submitStatUnit } } = this.props
    const data = Object.entries(formData)
      .reduce(
        (acc, [k, v]) => ({ ...acc, [k]: v === '' ? null : v }),
        { type },
      )
    submitStatUnit(data)
  }

  renderForm() {
    const { errors, statUnitModel, type, localize } = this.props

    const renderButton = () => (
      <Button key="100500" className={styles.sybbtn} type="submit" primary>
        {localize('Submit')}
      </Button>
    )

    const children = [
      ...statUnitModel.properties.map(x => getField(x, errors[x.name], this.handleOnChange)),
      <br key="br_100500" />,
      renderButton(),
    ]

    const data = { ...getModel(statUnitModel.properties), type }

    return (
      <SchemaForm
        className={styles.form}
        onSubmit={this.handleSubmit}
        error
        data={data}
        schema={statUnitSchema}
      >{children}</SchemaForm>
    )
  }

  render() {
    const { actions: { changeType }, type, localize } = this.props

    const statUnitTypeOptions =
      [...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) }))

    const handleTypeEdit = (e, { value }) => {
      if (type !== value) changeType(value)
    }

    return (
      <div className={styles.edit}>
        <Form.Select
          name="type"
          options={statUnitTypeOptions}
          value={type}
          onChange={handleTypeEdit}
        />
        {this.renderForm()}
      </div>
    )
  }
}

export default wrapper(CreateStatUnitPage)

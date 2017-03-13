import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Icon } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import SchemaForm from 'components/Form'
import getField from 'components/getField'
import { wrapper } from 'helpers/locale'
import { getModel } from 'helpers/modelProperties'
import styles from './styles.pcss'
import { getSchema } from '../schema'

const { shape, func, number } = React.PropTypes

class CreateStatUnitPage extends React.Component {

  static propTypes = {
    actions: shape({
      changeType: func.isRequired,
      submitStatUnit: func.isRequired,
    }).isRequired,
    type: number.isRequired,
    localize: func.isRequired,
    statUnitModel: shape().isRequired,
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

  handleSubmit = (e) => {
    e.preventDefault()
    const { type, statUnitModel, actions: { submitStatUnit } } = this.props
    const data = { ...getModel(statUnitModel.properties), type }
    submitStatUnit(data)
  }

  renderForm() {
    const { errors, statUnitModel, type, localize } = this.props

    const renderSubmitButton = () => (
      <Button
        content={localize('Submit')}
        key="100500"
        type="submit"
        floated="right"
        primary
      />
    )

    const renderBackButton = () => (
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
        size="small"
        color="grey"
        type="button"
        key="back_100500"
      />
    )

    const children = [
      ...statUnitModel.properties.map(x => getField(x, errors[x.name], this.handleOnChange)),
      <br key="br_100500" />,
      renderBackButton(),
      renderSubmitButton(),
    ]

    const data = { ...getModel(statUnitModel.properties), type }

    return (
      <SchemaForm
        className={styles.form}
        onSubmit={this.handleSubmit}
        error
        data={data}
        schema={getSchema(type)}
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
